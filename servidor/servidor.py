#!/usr/bin/env python3
import asyncio
import websockets
import cv2
import mediapipe as mp

# IDs de landmarks a enviar (puedes modificar esta lista para cambiar los puntos)
LANDMARK_IDS = [0] + list(range(11, 17)) + [23, 24, 25, 26, 27, 28]

# Variables globales para almacenar las posiciones de los puntos
pos_nodos = {i: (0, 0, 0) for i in LANDMARK_IDS}
clientes_conectados = set()

async def manejar_cliente(websocket):
    print(f"Cliente conectado desde: {websocket.remote_address}")
    clientes_conectados.add(websocket)
    try:
        async for mensaje in websocket:
            if mensaje == "estado_teclas":
                # Formato: N11_XX_YY_ZZ,N12_XX_YY_ZZ,...
                resp = []
                for idx in LANDMARK_IDS:
                    x, y, z = pos_nodos[idx]
                    resp.append(f"N{idx}_{x}_{y}_{z}")
                await websocket.send(",".join(resp))
    except websockets.exceptions.ConnectionClosed:
        print("Cliente desconectado")
    except Exception as e:
        print(f"Error: {e}")
    finally:
        clientes_conectados.discard(websocket)



# Bucle para capturar los puntos de MediaPipe en un hilo aparte
def bucle_mediapipe():
    global pos_nodos
    mp_pose = mp.solutions.pose
    cap = cv2.VideoCapture(0)
    with mp_pose.Pose(static_image_mode=False, min_detection_confidence=0.5, min_tracking_confidence=0.5) as pose:
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
                    landmark = results.pose_landmarks.landmark[idx]
                    x = int(landmark.x * frame.shape[1])
                    y = int(landmark.y * frame.shape[0])
                    z = int(landmark.z * 100.0)
                    pos_nodos[idx] = (x, y, z)
                    # Dibujar círculo en la imagen
                    cv2.circle(image_bgr, (x, y), 6, (0, 255, 0), -1)
                    cv2.putText(image_bgr, f"N{idx}", (x+8, y-8), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0,255,0), 1)
            # Mostrar ventana con la imagen y los puntos
            cv2.imshow('MediaPipe Landmarks', image_bgr)
            if cv2.waitKey(1) & 0xFF == 27:
                break
    cap.release()
    cv2.destroyAllWindows()


async def main():
    host = "0.0.0.0"
    puerto = 8765
    print(f"Iniciando servidor WebSocket en ws://{host}:{puerto}")

    # Lanzar el bucle de MediaPipe en un hilo aparte
    import threading
    t = threading.Thread(target=bucle_mediapipe, daemon=True)
    t.start()

    async with websockets.serve(manejar_cliente, host, puerto):
        print("Servidor WebSocket iniciado. Presiona Ctrl+C para salir.")
        await asyncio.Future()  # Esperar para siempre

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nCerrando servidor...")
    except Exception as e:
        print(f"Error: {e}")