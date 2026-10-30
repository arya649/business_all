# Site gateway (weighbridge scale and biometric machine)

A small Node program for the PC at the plant. It needs Node 18+ and nothing else.

1. In the app: Admin → Devices → add a "Weighbridge scale" and/or "Biometric machine". Copy the serial and key.
2. Copy `gateway.example.json` to `gateway.json` and fill in the project URL, the publishable key and the device serials/keys.
3. Weighbridge: connect the indicator's RS-232 to USB. On Linux set the port speed once
   (`stty -F /dev/ttyUSB0 2400 cs8 -cstopb -parenb raw`), or use `"tcp": {"host": "...", "port": 4001}` for Ethernet indicators.
   The operator's screen or an ANPR camera sends the vehicle number to `POST http://<pc>:8085/vehicle`.
   A weight is sent only when it has been steady for 3 seconds; the first weighment opens a ticket, the second completes it.
4. Biometric: in the machine's Comm → Cloud Server settings, enter this PC's IP and port 8081. Employee codes in the
   app must equal the machine's user IDs (with `code_prefix` if you use one).
5. Run `node gateway.mjs` (as a service with pm2 or systemd). Entries wait in `queue.json` while the internet is down.

GPS vendors: give them the URL `https://<project>.supabase.co/rest/v1/rpc/device_ingest` with header `apikey`, and body
`{"p_serial": "...", "p_key": "...", "p_payload": {"vehicle_no": "...", "lat": .., "lng": .., "speed_kmph": .., "odometer": .., "fuel_l": ..}}`.
