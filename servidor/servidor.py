#!/usr/bin/env python3
import asyncio
import json
import time
import threading
import websockets
import cv2
import mediapipe as mp

LANDMARK_IDS = [0] + list(range(11, 17)) + [23, 24, 25, 26, 27, 28]

LANDMARK_NAMES = {
    0:  "nose",
    11: "left_shoulder",
    12: "right_shoulder",
    13: "left_elbow",
    14: "right_elbow",
    15: "left_wrist",
    16: "right_wrist",
    23: "left_hip",
    24: "right_hip",
    25: "left_knee",
    26: "right_knee",
    27: "left_ankle",
    28: "right_ankle",
}

# Coords normalizadas: x,y en [0,1], z profundidad relativa de MediaPipe
pos_nodos = {i: (0.5, 0.5, 0.0) for i in LANDMARK_IDS}
clientes_conectados = set()


async def manejar_cliente(websocket):
    print(f"Cliente conectado desde: {websocket.remote_address}")
    clientes_conectados.add(websocket)
    try:
        await websocket.wait_closed()
    except Exception as e:
        print(f"Error: {e}")
    finally:
        clientes_conectados.discard(websocket)
        print("Cliente desconectado")


async def broadcast_loop():
    """Empuja landmarks JSON a todos los clientes a ~30 fps."""
    while True:
        if clientes_conectados:
            landmarks = [
                {
                    "id":   idx,
                    "name": LANDMARK_NAMES[idx],
                    "x":    round(pos_nodos[idx][0], 4),
                    "y":    round(pos_nodos[idx][1], 4),
                    "z":    round(pos_nodos[idx][2], 4),
                }
                for idx in LANDMARK_IDS
            ]
            mensaje = json.dumps({"landmarks": landmarks, "timestamp": time.time()})
            muertos = set()
            for ws in clientes_conectados.copy():
                try:
                    await ws.send(mensaje)
                except Exception:
                    muertos.add(ws)
            clientes_conectados -= muertos
        await asyncio.sleep(1 / 30)


def bucle_mediapipe():
    global pos_nodos
    mp_pose = mp.solutions.pose
    cap = cv2.VideoCapture(0)
    with mp_pose.Pose(
        static_image_mode=False,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    ) as pose:
        while True:
            ret, frame = cap.read()
            if not ret:
                continue
            frame = cv2.flip(frame, 1)
            image = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            image.flags.writeable = False
            results = pose.process(image)
            image.flags.writeable = True
            image_bgr = cv2.cvtColor(image, cv2.COLOR_RGB2BGR)
            if results.pose_landmarks:
                for idx in LANDMARK_IDS:
                    lm = results.pose_landmarks.landmark[idx]
                    pos_nodos[idx] = (lm.x, lm.y, lm.z)
                    x_px = int(lm.x * frame.shape[1])
                    y_px = int(lm.y * frame.shape[0])
                    cv2.circle(image_bgr, (x_px, y_px), 6, (0, 255, 0), -1)
                    cv2.putText(
                        image_bgr, f"N{idx}", (x_px + 8, y_px - 8),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1,
                    )
            cv2.imshow("MediaPipe Landmarks", image_bgr)
            if cv2.waitKey(1) & 0xFF == 27:
                break
    cap.release()
    cv2.destroyAllWindows()


async def main():
    host = "0.0.0.0"
    puerto = 8765
    print(f"Iniciando servidor WebSocket en ws://{host}:{puerto}")
    threading.Thread(target=bucle_mediapipe, daemon=True).start()
    async with websockets.serve(manejar_cliente, host, puerto):
        print("Servidor listo. Ctrl+C para salir.")
        await broadcast_loop()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nCerrando servidor...")
    except Exception as e:
        print(f"Error: {e}")
