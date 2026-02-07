 void setup() {
  Serial.begin(115200);
}

void loop() {
  int xaxis = analogRead(A0);
  int yaxis = analogRead(A1);
  int zaxis = analogRead(A2);

  // Space-separated values
  Serial.print(xaxis);
  Serial.print(" ");
  Serial.print(yaxis);
  Serial.print(" ");
  Serial.println(zaxis);

  delay(50);  // ~20 Hz
}
