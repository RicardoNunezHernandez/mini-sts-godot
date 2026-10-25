#!/usr/bin/env python3
"""Simula las palancas físicas enviando su posición por UDP al simulador.

Sirve para probar la conexión sin hardware. Un ESP32 con las palancas reales
enviaría exactamente el mismo mensaje JSON.

Ejemplos:
    python3 tools/simular_palancas.py --carro 0.5 --segundos 3
    python3 tools/simular_palancas.py --demo
"""

import argparse
import json
import math
import socket
import time

FRECUENCIA_HZ = 30


def enviar(sock, destino, gantry, trolley, hoist, lock):
    mensaje = {"gantry": gantry, "trolley": trolley, "hoist": hoist, "lock": lock}
    sock.sendto(json.dumps(mensaje).encode("utf-8"), destino)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--puerto", type=int, default=4242)
    parser.add_argument("--portico", type=float, default=0.0, help="-1 a 1 (+ = hacia +X)")
    parser.add_argument("--carro", type=float, default=0.0, help="-1 a 1 (+ = hacia tierra)")
    parser.add_argument("--izaje", type=float, default=0.0, help="-1 a 1 (+ = subir)")
    parser.add_argument("--twistlocks", action="store_true", help="pulsa el botón de twistlocks una vez")
    parser.add_argument("--segundos", type=float, default=2.0)
    parser.add_argument("--demo", action="store_true", help="mueve el carro de lado a lado durante 20 s")
    args = parser.parse_args()

    destino = (args.host, args.puerto)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    inicio = time.monotonic()
    duracion = 20.0 if args.demo else args.segundos
    while (transcurrido := time.monotonic() - inicio) < duracion:
        if args.demo:
            enviar(sock, destino, 0.0, math.sin(transcurrido * 0.6), 0.0, False)
        else:
            # El botón queda pulsado sólo durante el primer cuarto de segundo.
            pulsado = args.twistlocks and transcurrido < 0.25
            enviar(sock, destino, args.portico, args.carro, args.izaje, pulsado)
        time.sleep(1.0 / FRECUENCIA_HZ)
    # Al terminar, palancas al centro.
    enviar(sock, destino, 0.0, 0.0, 0.0, False)
    print(f"Enviado a {destino[0]}:{destino[1]} durante {duracion:.1f} s")


if __name__ == "__main__":
    main()
