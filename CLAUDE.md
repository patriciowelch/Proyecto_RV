# Hole in the Wall VR — Informe del Proyecto

## Resumen

Proyecto universitario para la materia de **Realidad Virtual**. Se replica el juego de televisión *"Hole in the Wall"* (Human Tetris): el jugador debe imitar la silueta de un agujero en una pared que avanza hacia él para no ser empujado al agua.

La experiencia es en **primera persona con Cardboard VR** desde un teléfono Android. La detección del cuerpo del jugador se hace en tiempo real desde una PC con cámara, usando visión por computadora.

---

## Arquitectura General

```
[Cámara de la PC]
       ↓
[Python + MediaPipe]     ← detecta la pose del jugador en tiempo real
       ↓
[WebSocket Server]       ← serializa y transmite los landmarks por red local (WiFi)
       ↓  (misma red WiFi)
[Android — Godot 4]      ← recibe los datos del cuerpo del jugador
       ↓
[Lógica del juego]       ← compara la silueta del jugador vs el agujero de la pared
       ↓
[Cardboard VR]           ← renderiza la escena en modo estereoscópico
```

---

## Componentes

### 1. PC — Python + MediaPipe (servidor)

**Responsabilidad:** capturar la imagen de la cámara, detectar la pose del jugador y transmitir los datos.

- **MediaPipe Pose** detecta 33 landmarks 3D del cuerpo humano en cada frame.
- Solo se usan los landmarks relevantes para el juego: hombros, codos, muñecas, caderas, rodillas y tobillos (proyección 2D frontal — ejes X e Y normalizados entre 0 y 1).
- Un **servidor WebSocket** (`websockets` / `asyncio`) publica los landmarks como JSON a ~30 fps.
- La PC y el teléfono deben estar en la **misma red WiFi local**.

**Formato del mensaje enviado:**
```json
{
  "landmarks": [
    { "id": 11, "name": "left_shoulder",  "x": 0.42, "y": 0.31 },
    { "id": 12, "name": "right_shoulder", "x": 0.58, "y": 0.31 },
    { "id": 13, "name": "left_elbow",     "x": 0.38, "y": 0.48 },
    { "id": 14, "name": "right_elbow",    "x": 0.62, "y": 0.48 },
    { "id": 15, "name": "left_wrist",     "x": 0.35, "y": 0.63 },
    { "id": 16, "name": "right_wrist",    "x": 0.65, "y": 0.63 },
    { "id": 23, "name": "left_hip",       "x": 0.44, "y": 0.58 },
    { "id": 24, "name": "right_hip",      "x": 0.56, "y": 0.58 },
    { "id": 25, "name": "left_knee",      "x": 0.43, "y": 0.74 },
    { "id": 26, "name": "right_knee",     "x": 0.57, "y": 0.74 },
    { "id": 27, "name": "left_ankle",     "x": 0.43, "y": 0.89 },
    { "id": 28, "name": "right_ankle",    "x": 0.57, "y": 0.89 }
  ],
  "timestamp": 1717900000.123
}
```

---

### 2. Android — Godot 4 (cliente VR)

**Responsabilidad:** presentar la experiencia de juego en Cardboard VR y evaluar si el jugador pasa la pared.

#### Subsistemas principales

**WebSocket Client**
- Se conecta al servidor Python al iniciar la escena.
- Escucha mensajes entrantes en cada frame (`_process`).
- Maneja reconexión automática si se pierde la señal.
- Los landmarks recibidos se convierten en coordenadas de pantalla para la lógica del juego.

**Lógica del juego**
- La **pared con el agujero** avanza hacia el jugador a velocidad configurable.
- El **agujero** es un polígono 2D (definido por el diseño del nivel).
- La **silueta del jugador** se construye a partir de los landmarks recibidos.
- Comparación: se verifica si los puntos clave del esqueleto del jugador están contenidos dentro del polígono del agujero.
- Si algún punto queda fuera cuando la pared llega al plano del jugador → el jugador pierde y es "empujado al agua".

**Renderizado Cardboard VR**
- Se usa el **plugin oficial de Google Cardboard SDK para Godot 4**.
- La cámara se divide en dos viewports (ojo izquierdo / ojo derecho) con distorsión de lente.
- El jugador ve la escena en primera persona desde detrás de la pared que se acerca.

---

## Flujo de una ronda

```
1. El jugador se para frente a la cámara de la PC.
2. Python detecta su pose y empieza a transmitir landmarks por WebSocket.
3. Godot recibe los datos y dibuja la silueta del jugador en la escena VR.
4. La pared con el agujero empieza a avanzar.
5. El jugador tiene X segundos para adoptar la postura correcta.
6. Cuando la pared llega al plano del jugador, Godot evalúa si la silueta encaja.
7. Si encaja → el jugador pasa → la pared continúa o aparece una nueva.
8. Si no encaja → animación de caída al agua → fin de ronda.
```

---

## Configuración de red

| Parámetro | Valor de ejemplo |
|-----------|-----------------|
| IP del servidor (PC) | `192.168.1.100` |
| Puerto WebSocket | `8765` |
| Protocolo | `ws://` (sin TLS, red local) |
| Frecuencia de envío | ~30 fps |

> **Importante:** tanto la PC como el teléfono Android deben estar conectados a la misma red WiFi. No funciona con datos móviles.

---

## Dependencias

### Python (PC)
```
mediapipe
opencv-python
websockets
asyncio
```

### Godot 4 (Android)
- Plugin: **Google Cardboard XR Plugin for Godot**
- Android SDK configurado con nivel de API mínimo 24
- APK firmado (puede ser con clave de debug para pruebas)

---

## Estado actual del proyecto

- [ ] Servidor Python con MediaPipe y WebSocket
- [ ] Cliente WebSocket en Godot
- [ ] Lógica de comparación silueta vs agujero
- [ ] Integración Cardboard VR
- [ ] Exportación APK y pruebas en dispositivo

---

## Notas para Claude Code

- El proyecto tiene **dos repositorios o carpetas separadas**: una para Python (servidor) y otra para el proyecto Godot 4.
- La lógica más delicada es la **comparación de silueta**: hay que definir si se usa bounding box simplificada o overlap de polígonos real.
- La **latencia del WebSocket** es el riesgo principal: el cliente Godot debe tolerar frames perdidos sin congelarse.
- Priorizar que el juego funcione en una misma red WiFi hogareña antes de optimizar rendimiento.
