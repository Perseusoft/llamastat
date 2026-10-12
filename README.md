# llamacpp-local

Stack de modelos locales en macOS con [llama.cpp](https://github.com/ggml-org/llama.cpp) en modo router
(un solo `llama-server` que carga/descarga modelos bajo demanda, máx. 1 a la vez).

## Contenido

| Ruta | Qué es | Se instala en |
|---|---|---|
| `models/presets.ini` | Modelos disponibles para el router | `~/models/presets.ini` (symlink) |
| `launchd/com.local.llama-router.plist` | LaunchAgent del router (:8080) | `~/Library/LaunchAgents/` (copia) |
| `xbar/llamacpp.10s.sh` | Plugin de barra de menú: estado, RAM/swap, cargar/descargar | plugins de xbar (symlink) |
| `install.sh` | Enlaza todo lo anterior y reinicia el router | — |
| `start.sh` | Levanta router + xbar y lista modelos | — |

Los `.gguf` viven en `~/models/` y no se versionan.

## Uso

```bash
brew install llama.cpp
./install.sh
./start.sh
```

- OpenAI-compatible: `http://localhost:8080/v1`
- Anthropic-compatible: `http://localhost:8080/v1/messages` (alias `claude-local` en `~/.zshrc`)

Agregar un modelo: poner el `.gguf` en `~/models/`, añadir una sección a `models/presets.ini` y
"Reiniciar router" desde el menú de xbar.

## Notas

- Máquina con 24 GB: no correr dos modelos de ~20B a la vez (por eso `--models-max 1`).
- Los modelos se descargan solos tras 15 min sin uso (`--sleep-idle-seconds 900`).
