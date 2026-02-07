"""
STREAMING REAL-TIME REP COUNTER (Fully Online)
================================================

Processes accelerometer data sample-by-sample with:
- Online PCA (incremental covariance + eigendecomposition of 3x3 matrix)
- Causal smoothing (exponential moving average, no future samples needed)
- Peak-valley state machine for rep counting
- Adaptive baseline tracking

Everything runs per-sample — no batch operations, no lookahead.
"""

import numpy as np
import matplotlib.pyplot as plt
import time

try:
    from IPython.display import clear_output
    COLAB_AVAILABLE = True
except ImportError:
    COLAB_AVAILABLE = False


class StreamingPCA:
    """
    Online PCA using Welford's algorithm for incremental mean/covariance.

    For 3-axis accelerometer data, the covariance matrix is only 3x3,
    so eigendecomposition is essentially free (~microseconds).

    During warmup (first N samples), returns signal magnitude instead.
    """

    def __init__(self, n_dims=3, warmup=30):
        """
        Parameters:
        -----------
        n_dims : int
            Dimensionality of input (3 for accelerometer)
        warmup : int
            Samples before PCA starts (need enough for stable covariance)
        """
        self.n_dims = n_dims
        self.warmup = warmup
        self.n = 0
        self.mean = np.zeros(n_dims)
        self.C = np.zeros((n_dims, n_dims))  # Running sum for covariance
        self.prev_pc1 = None  # Track previous eigenvector to fix sign flips

    def update(self, x):
        """
        Process one 3-axis sample and return its PC1 projection.

        Parameters:
        -----------
        x : array-like, shape (3,)
            One accelerometer reading [ax, ay, az]

        Returns:
        --------
        float : PC1 projection of this sample
        """
        x = np.asarray(x, dtype=float)
        self.n += 1

        # Welford's online update for mean and covariance
        delta = x - self.mean
        self.mean += delta / self.n
        delta2 = x - self.mean
        self.C += np.outer(delta, delta2)

        if self.n < self.warmup:
            # Not enough samples for stable PCA — use magnitude as fallback
            return np.linalg.norm(x - self.mean)

        # Covariance matrix (divide by n, not n-1, for stability at small n)
        cov = self.C / self.n

        # Eigendecomposition of 3x3 matrix (trivially fast)
        eigenvalues, eigenvectors = np.linalg.eigh(cov)

        # eigh returns ascending order — last column is largest eigenvalue
        pc1 = eigenvectors[:, -1]

        # Fix sign flips: ensure consistent direction with previous frame
        if self.prev_pc1 is not None:
            if np.dot(pc1, self.prev_pc1) < 0:
                pc1 = -pc1
        self.prev_pc1 = pc1.copy()

        # Project centered sample onto PC1
        return float(np.dot(x - self.mean, pc1))

    def get_explained_variance_ratio(self):
        """Return how much variance PC1 explains (call after warmup)."""
        if self.n < self.warmup:
            return 0.0
        cov = self.C / self.n
        eigenvalues = np.linalg.eigvalsh(cov)
        total = eigenvalues.sum()
        if total == 0:
            return 0.0
        return float(eigenvalues[-1] / total)


class StreamingSmoother:
    """
    Causal exponential moving average smoother.

    Unlike savgol_filter (which needs future samples), EMA only uses
    past and current data — perfect for real-time streaming.

    y_t = alpha * x_t + (1 - alpha) * y_{t-1}

    Lower alpha = more smoothing (slower response)
    Higher alpha = less smoothing (faster response, more noise)
    """

    def __init__(self, alpha=0.15):
        self.alpha = alpha
        self.value = None

    def update(self, x):
        if self.value is None:
            self.value = x
        else:
            self.value = self.alpha * x + (1 - self.alpha) * self.value
        return self.value

    def reset(self):
        self.value = None


class StreamingRepCounter:
    """
    Real-time rep counter using peak-valley state machine.

    1. Tracks adaptive baseline (running mean of PC1)
    2. Detects peaks (signal goes up then down)
    3. Detects valleys (signal goes down then up)
    4. Counts rep when peak-to-valley amplitude > threshold
    """

    def __init__(self,
                 amplitude_threshold=25.0,
                 min_samples_between_reps=20,
                 baseline_window=50):
        self.amplitude_threshold = amplitude_threshold
        self.min_samples_between_reps = min_samples_between_reps
        self.baseline_window = baseline_window

        # State machine
        self.state = 'WAITING_FOR_PEAK'
        self.rep_count = 0
        self.samples_since_last_rep = 0

        # Peak/valley tracking
        self.current_peak = None
        self.current_valley = None
        self.peak_sample_idx = None
        self.valley_sample_idx = None

        # Baseline calculation
        self.recent_samples = []
        self.baseline = 0

        # History for visualization
        self.signal_history = []
        self.baseline_history = []
        self.state_history = []
        self.rep_detection_samples = []
        self.rep_amplitudes = []

    def process_sample(self, signal_value, sample_idx):
        """
        Process ONE sample.

        Returns dict with rep_count, state, rep_detected, etc.
        """
        self.samples_since_last_rep += 1
        rep_detected = False
        amplitude = 0

        # Update adaptive baseline
        self.recent_samples.append(signal_value)
        if len(self.recent_samples) > self.baseline_window:
            self.recent_samples.pop(0)
        self.baseline = np.mean(self.recent_samples)

        # Center signal around baseline
        signal_centered = signal_value - self.baseline

        # STATE MACHINE
        if self.state == 'WAITING_FOR_PEAK':
            if self.current_peak is None or signal_centered > self.current_peak:
                self.current_peak = signal_centered
                self.peak_sample_idx = sample_idx

            if self.current_peak is not None and signal_centered < self.current_peak - 3:
                self.state = 'WAITING_FOR_VALLEY'
                self.current_valley = signal_centered
                self.valley_sample_idx = sample_idx

        elif self.state == 'WAITING_FOR_VALLEY':
            if signal_centered < self.current_valley:
                self.current_valley = signal_centered
                self.valley_sample_idx = sample_idx

            if signal_centered > self.current_valley + 3:
                amplitude = self.current_peak - self.current_valley

                if (amplitude > self.amplitude_threshold and
                    self.samples_since_last_rep > self.min_samples_between_reps):
                    self.rep_count += 1
                    self.rep_detection_samples.append(self.valley_sample_idx)
                    self.rep_amplitudes.append(amplitude)
                    self.samples_since_last_rep = 0
                    rep_detected = True

                self.state = 'WAITING_FOR_PEAK'
                self.current_peak = signal_centered
                self.peak_sample_idx = sample_idx
                self.current_valley = None

        # Store history
        self.signal_history.append(signal_value)
        self.baseline_history.append(self.baseline)
        self.state_history.append(self.state)

        return {
            'rep_count': self.rep_count,
            'state': self.state,
            'baseline': self.baseline,
            'rep_detected': rep_detected,
            'amplitude': amplitude if self.state == 'WAITING_FOR_VALLEY' else 0
        }

    def reset(self):
        self.__init__(self.amplitude_threshold,
                     self.min_samples_between_reps,
                     self.baseline_window)

    def get_summary(self):
        return {
            'total_reps': self.rep_count,
            'rep_samples': self.rep_detection_samples,
            'rep_amplitudes': self.rep_amplitudes,
            'signal': np.array(self.signal_history),
            'baseline': np.array(self.baseline_history),
            'states': self.state_history
        }


class StreamingPipeline:
    """
    Complete streaming pipeline: raw 3-axis sample -> PCA -> smooth -> rep count.

    Every operation is online/causal — no batch preprocessing needed.
    """

    def __init__(self,
                 amplitude_threshold=25.0,
                 min_samples_between_reps=20,
                 baseline_window=50,
                 pca_warmup=30,
                 smooth_alpha=0.15):

        self.pca = StreamingPCA(n_dims=3, warmup=pca_warmup)
        self.smoother = StreamingSmoother(alpha=smooth_alpha)
        self.counter = StreamingRepCounter(
            amplitude_threshold=amplitude_threshold,
            min_samples_between_reps=min_samples_between_reps,
            baseline_window=baseline_window
        )

        # Store raw + intermediate signals for visualization
        self.raw_history = []
        self.pc1_raw_history = []
        self.pc1_smooth_history = []

    def process_sample(self, ax, ay, az, sample_idx):
        """
        Process one raw accelerometer reading.

        Parameters:
        -----------
        ax, ay, az : float
            Raw accelerometer values
        sample_idx : int
            Sample number

        Returns:
        --------
        dict with rep_count, rep_detected, state, etc.
        """
        raw = np.array([ax, ay, az])
        self.raw_history.append(raw)

        # Step 1: Online PCA projection
        pc1_value = self.pca.update(raw)
        self.pc1_raw_history.append(pc1_value)

        # Step 2: Causal smoothing
        pc1_smooth = self.smoother.update(pc1_value)
        self.pc1_smooth_history.append(pc1_smooth)

        # Step 3: Rep detection
        result = self.counter.process_sample(pc1_smooth, sample_idx)

        return result

    def get_raw_data(self):
        return np.array(self.raw_history)

    def get_pc1_raw(self):
        return np.array(self.pc1_raw_history)

    def get_pc1_smooth(self):
        return np.array(self.pc1_smooth_history)


def load_imu_data(filepath):
    """Load raw IMU data from file (3 columns: x, y, z)."""
    data = []
    with open(filepath, 'r') as f:
        for line in f:
            values = line.strip().split()
            if len(values) == 3:
                data.append([int(v) for v in values])
    data = np.array(data)
    print(f"Loaded {len(data)} samples from {filepath}")
    return data


def simulate_streaming(raw_data, pipeline, delay_ms=0, verbose=True):
    """
    Simulate real-time streaming through the full pipeline.

    Each sample goes through: raw -> PCA -> smooth -> rep detect
    """
    results = []

    print("\n" + "=" * 70)
    print("STARTING FULLY ONLINE STREAMING SIMULATION...")
    print("  - PCA: computed incrementally (Welford's covariance)")
    print("  - Smoothing: causal EMA (no future samples)")
    print("  - Rep detection: peak-valley state machine")
    print("=" * 70)

    for i, sample in enumerate(raw_data):
        result = pipeline.process_sample(sample[0], sample[1], sample[2], i)
        results.append(result)

        if result['rep_detected'] and verbose:
            print(f"  REP {result['rep_count']} detected at sample {i}")

        if delay_ms > 0:
            time.sleep(delay_ms / 1000.0)

    explained = pipeline.pca.get_explained_variance_ratio()
    print(f"\nPC1 explains {explained*100:.1f}% of variance (final estimate)")
    print("=" * 70)
    print(f"FINAL COUNT: {pipeline.counter.rep_count} reps")
    print("=" * 70)

    return results


def plot_streaming_results(pipeline, figsize=(16, 12), save_path=None):
    """Visualize the fully online streaming results."""

    raw_data = pipeline.get_raw_data()
    pc1_raw = pipeline.get_pc1_raw()
    pc1_smooth = pipeline.get_pc1_smooth()
    summary = pipeline.counter.get_summary()

    n_samples = len(raw_data)
    t = np.arange(n_samples)

    signal = summary['signal']
    baseline = summary['baseline']
    rep_samples = summary['rep_samples']
    total_reps = summary['total_reps']

    fig, axes = plt.subplots(5, 1, figsize=figsize)

    # 1. Raw accelerometer
    axes[0].plot(t, raw_data[:, 0], 'r-', alpha=0.6, linewidth=1, label='X')
    axes[0].plot(t, raw_data[:, 1], 'g-', alpha=0.6, linewidth=1, label='Y')
    axes[0].plot(t, raw_data[:, 2], 'b-', alpha=0.6, linewidth=1, label='Z')
    axes[0].set_ylabel('Raw Accel', fontsize=11, fontweight='bold')
    axes[0].set_title('Raw 3-Axis Accelerometer Data', fontsize=13, fontweight='bold')
    axes[0].legend(loc='upper right', ncol=3)
    axes[0].grid(True, alpha=0.3)

    # 2. Online PCA output (raw vs smoothed)
    warmup = pipeline.pca.warmup
    axes[1].axvspan(0, warmup, alpha=0.1, color='red', label=f'PCA warmup ({warmup} samples)')
    axes[1].plot(t, pc1_raw, 'gray', linewidth=0.8, alpha=0.5, label='PC1 (raw)')
    axes[1].plot(t, pc1_smooth, 'black', linewidth=2, label='PC1 (EMA smoothed)')
    axes[1].set_ylabel('PC1', fontsize=11, fontweight='bold')
    axes[1].set_title('Online PCA Projection (incremental covariance)',
                      fontsize=13, fontweight='bold')
    axes[1].legend(loc='upper right')
    axes[1].grid(True, alpha=0.3)

    # 3. Signal with adaptive baseline
    axes[2].plot(t, signal, 'black', linewidth=2, label='PC1 (smoothed)', alpha=0.8)
    axes[2].plot(t, baseline, 'orange', linewidth=2.5, linestyle='--',
                 label='Adaptive Baseline', alpha=0.8)
    axes[2].fill_between(t, baseline, signal,
                         where=(signal >= baseline),
                         alpha=0.2, color='green', label='Above baseline')
    axes[2].fill_between(t, baseline, signal,
                         where=(signal < baseline),
                         alpha=0.2, color='red', label='Below baseline')
    axes[2].set_ylabel('Signal', fontsize=11, fontweight='bold')
    axes[2].set_title('Signal with Adaptive Baseline', fontsize=13, fontweight='bold')
    axes[2].legend(loc='upper right')
    axes[2].grid(True, alpha=0.3)

    # 4. Centered signal with rep detections
    centered = signal - baseline
    axes[3].plot(t, centered, 'darkblue', linewidth=2, label='Centered Signal')
    axes[3].axhline(0, color='gray', linestyle='--', alpha=0.5, linewidth=1.5)
    thresh = pipeline.counter.amplitude_threshold
    axes[3].axhline(thresh, color='red', linestyle=':', alpha=0.5, linewidth=2,
                     label=f'Threshold ({thresh})')
    axes[3].axhline(-thresh, color='red', linestyle=':', alpha=0.5, linewidth=2)

    if len(rep_samples) > 0:
        axes[3].scatter(rep_samples, centered[rep_samples],
                        color='red', s=300, marker='*',
                        edgecolors='darkred', linewidths=3,
                        label=f'Reps ({total_reps})', zorder=5)
        for idx in rep_samples:
            axes[3].axvline(idx, color='red', alpha=0.2, linewidth=2, linestyle='--')

    axes[3].set_ylabel('Centered', fontsize=11, fontweight='bold')
    axes[3].set_title('Rep Detection', fontsize=13, fontweight='bold', color='darkgreen')
    axes[3].legend(loc='upper right')
    axes[3].grid(True, alpha=0.3)

    # 5. Cumulative rep count
    cumulative = np.zeros(n_samples)
    for rep_num, idx in enumerate(rep_samples, 1):
        cumulative[idx:] = rep_num

    axes[4].plot(t, cumulative, 'darkgreen', linewidth=4, drawstyle='steps-post')
    axes[4].fill_between(t, cumulative, alpha=0.3, color='green', step='post')

    if len(rep_samples) > 0:
        axes[4].scatter(rep_samples, cumulative[rep_samples],
                        color='red', s=250, marker='o',
                        edgecolors='darkred', linewidths=3, zorder=5)
        for rep_num, idx in enumerate(rep_samples, 1):
            axes[4].annotate(f'Rep {rep_num}\n(sample {idx})',
                             xy=(idx, cumulative[idx]),
                             xytext=(15, 15), textcoords='offset points',
                             fontsize=10, fontweight='bold',
                             bbox=dict(boxstyle='round,pad=0.5',
                                       facecolor='yellow', alpha=0.8),
                             arrowprops=dict(arrowstyle='->',
                                             connectionstyle='arc3,rad=0.2', lw=2))

    axes[4].set_ylabel('Total Reps', fontsize=11, fontweight='bold')
    axes[4].set_xlabel('Sample Index', fontsize=11, fontweight='bold')
    axes[4].set_title(f'Cumulative Rep Count - TOTAL: {total_reps} REPS',
                      fontsize=14, fontweight='bold', color='darkgreen', pad=15)
    axes[4].grid(True, alpha=0.3)
    axes[4].set_ylim([-0.5, max(total_reps + 0.5, 1)])

    plt.tight_layout()

    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        print(f"\nPlot saved: {save_path}")

    return fig


# ============================================================================
# MAIN
# ============================================================================

if __name__ == "__main__":

    print("=" * 70)
    print("FULLY ONLINE STREAMING REP COUNTER")
    print("  No batch PCA, no lookahead smoothing — everything per-sample")
    print("=" * 70)

    # Step 1: Load raw data (this is the only "batch" step — reading the file)
    filepath = '/content/imu_20260206_231328.txt'
    raw_data = load_imu_data(filepath)

    # Step 2: Create the fully online pipeline
    pipeline = StreamingPipeline(
        amplitude_threshold=21.0,
        min_samples_between_reps=20,
        baseline_window=50,
        pca_warmup=30,       # Samples before PCA activates
        smooth_alpha=0.15,   # EMA smoothing (lower = smoother)
    )

    # Step 3: Stream sample-by-sample (everything computed online)
    results = simulate_streaming(
        raw_data,
        pipeline,
        delay_ms=10,
        verbose=True
    )

    # Step 4: Visualize
    print("\nGenerating visualization...")
    fig = plot_streaming_results(
        pipeline,
        save_path='streaming_rep_results.png'
    )

    # Step 5: Summary
    summary = pipeline.counter.get_summary()
    print(f"\nTotal Reps: {summary['total_reps']}")
    print(f"Rep Samples: {summary['rep_samples']}")
    print(f"Rep Amplitudes: {[f'{a:.1f}' for a in summary['rep_amplitudes']]}")
    print(f"PC1 Variance Explained: {pipeline.pca.get_explained_variance_ratio()*100:.1f}%")

    plt.show()
