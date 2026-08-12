#!/usr/bin/env python3
import asyncio
import json
import os
import time
import threading
import websockets
import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision

# MediaPipe 1.0 eliminó la API legacy `mp.solutions`, así que se usa la API
# Tasks, que necesita este modelo aparte (no viene con el paquete):
#   https://storage.googleapis.com/mediapipe-models/pose_landmarker/
#       pose_landmarker_lite/float16/1/pose_landmarker_lite.task
MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "pose_landmarker_lite.task")

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

# Último cuadro JPEG que mandó el visor con la vista del jugador. Se guarda crudo
# y lo decodifica el hilo de la cámara: las ventanas de OpenCV pertenecen a ese
# hilo y llamar a imshow desde el bucle asyncio cuelga en Windows.
ultimo_cuadro_visor = None
cuadros_recibidos = 0

# Comandos que se disparan con el teclado desde la ventana de la cámara y viajan
# al visor. Los encola el hilo de OpenCV y los vacía el bucle asyncio: append y
# pop son atómicos bajo el GIL, así que no hace falta un lock.
comandos_pendientes = []

# Último modo (sentado/parado) y última lista de poses que anunció alguien, tal
# como llegaron. Se reenvían a cada cliente nuevo.
ultima_config = None
ultimas_poses = None

# Tecla -> comando. Son las mismas acciones que los botones del control: 2
# arranca y frena, 3 calibra en T, y recentrar endereza la vista.
TECLAS = {
    13: 2,            # Enter
    ord(" "): 2,
    ord("c"): 3,
    ord("C"): 3,
    ord("r"): "recentrar",
    ord("R"): "recentrar",
}


async def manejar_cliente(websocket):
    global ultimo_cuadro_visor, cuadros_recibidos
    print(f"Cliente conectado desde: {websocket.remote_address}")
    clientes_conectados.add(websocket)
    # Al que llega tarde hay que ponerlo al día: el modo sentado y las poses
    # editadas se anuncian solo cuando cambian, así que sin esto un visor que
    # arranca después del espejo se quedaría con la configuración por defecto.
    try:
        for guardado in (ultima_config, ultimas_poses):
            if guardado is not None:
                await websocket.send(guardado)
    except Exception:
        pass
    try:
        # Por este canal, que es el mismo por el que se envían los landmarks,
        # el visor devuelve dos cosas: cuadros JPEG de la vista del jugador
        # (binario) y su estado de juego (texto JSON).
        async for mensaje in websocket:
            if isinstance(mensaje, (bytes, bytearray)):
                ultimo_cuadro_visor = bytes(mensaje)
                cuadros_recibidos += 1
            else:
                _recordar(mensaje)
                # El estado se retransmite tal cual a los demás clientes: el
                # espejo de la PC es otro cliente más y necesita recibirlo.
                await _retransmitir(mensaje, websocket)
    except Exception as e:
        print(f"Error: {e}")
    finally:
        clientes_conectados.discard(websocket)
        print("Cliente desconectado")


def _recordar(mensaje):
    """Guarda config y poses para poder repetírselas a quien se conecte luego.

    El estado del juego no se guarda: llega 30 veces por segundo y el que se
    conecta tarde tiene el siguiente en 33 ms.
    """
    global ultima_config, ultimas_poses
    try:
        d = json.loads(mensaje)
    except Exception:
        return
    if "cfg" in d:
        ultima_config = mensaje
    elif "poses" in d:
        ultimas_poses = mensaje


async def _retransmitir(mensaje, origen):
    """Reenvía un mensaje a todos los clientes menos al que lo mandó."""
    muertos = set()
    for otro in clientes_conectados.copy():
        if otro is origen:
            continue
        try:
            await otro.send(mensaje)
        except Exception:
            muertos.add(otro)
    clientes_conectados.difference_update(muertos)


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
            # In-place: `-=` rebindaría el nombre y lo volvería local a esta
            # función, rompiendo la lectura de más arriba con UnboundLocalError.
            clientes_conectados.difference_update(muertos)
        # Teclas apretadas en la ventana de la cámara, camino al visor.
        while comandos_pendientes:
            await _retransmitir(json.dumps({"cmd": comandos_pendientes.pop(0)}), None)
        await asyncio.sleep(1 / 30)


def bucle_mediapipe():
    global pos_nodos
    if not os.path.exists(MODEL_PATH):
        print(f"Falta el modelo: {MODEL_PATH}")
        return

    opciones = vision.PoseLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=MODEL_PATH),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
    )
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("No se pudo abrir la cámara.")
        return

    with vision.PoseLandmarker.create_from_options(opciones) as landmarker:
        while True:
            ret, frame = cap.read()
            if not ret:
                continue
            frame = cv2.flip(frame, 1)
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            imagen = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            # detect_for_video exige timestamps crecientes en milisegundos.
            resultado = landmarker.detect_for_video(imagen,
                                                    int(time.monotonic() * 1000))
            if resultado.pose_landmarks:
                marcas = resultado.pose_landmarks[0]
                for idx in LANDMARK_IDS:
                    lm = marcas[idx]
                    pos_nodos[idx] = (lm.x, lm.y, lm.z)
                    x_px = int(lm.x * frame.shape[1])
                    y_px = int(lm.y * frame.shape[0])
                    cv2.circle(frame, (x_px, y_px), 6, (0, 255, 0), -1)
                    cv2.putText(
                        frame, f"N{idx}", (x_px + 8, y_px - 8),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1,
                    )
            cv2.imshow("MediaPipe Landmarks", frame)
            _mostrar_vista_visor()
            tecla = cv2.waitKey(1) & 0xFF
            if tecla == 27:
                break
            if tecla in TECLAS:
                comandos_pendientes.append(TECLAS[tecla])
                print(f"[control] {TECLAS[tecla]}")
    cap.release()
    cv2.destroyAllWindows()


def _mostrar_vista_visor():
    """Dibuja el último cuadro que mandó el visor, si llegó alguno.

    Se decodifica acá y no en manejar_cliente para no meter trabajo de imagen
    dentro del bucle asyncio, que además tiene que seguir empujando landmarks.
    """
    datos = ultimo_cuadro_visor
    if datos is None:
        return
    buf = np.frombuffer(datos, dtype=np.uint8)
    img = cv2.imdecode(buf, cv2.IMREAD_COLOR)
    if img is not None:
        cv2.imshow("Vista del jugador", img)


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
