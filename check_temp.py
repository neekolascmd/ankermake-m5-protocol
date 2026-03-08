import asyncio
import websockets
import json

async def monitor():
    uri = "ws://127.0.0.1:4470/ws/mqtt"
    async with websockets.connect(uri) as websocket:
        print("Connected to MQTT Stream")
        for i in range(5):
            response = await websocket.recv()
            data = json.loads(response)
            if data.get("commandType") == 1001:
                nozzle_target = data.get("TargetToolTemp")
                nozzle_real = data.get("RealToolTemp")
                bed_target = data.get("TargetLayerTemp")
                bed_real = data.get("RealLayerTemp")
                print(f"[Telemetry] Nozzle: {nozzle_real}C / {nozzle_target}C \t Bed: {bed_real}C / {bed_target}C")

asyncio.run(monitor())
