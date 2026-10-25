# Guía de desarrollo: cómo se construyó y por qué

Este documento explica el simulador paso a paso, en el orden en que se construyó, y la razón de
cada decisión. La idea es que puedas leer el código con esta guía al lado y entender cada parte.

---

## 0. El problema que resuelve

Una grúa STS (*ship-to-shore*) descarga contenedores de un barco al muelle. El operador va sentado
en una cabina colgada del carro, a ~35 m de altura, mirando hacia abajo, y controla tres movimientos:

| Movimiento | Qué mueve | Eje en el simulador |
|---|---|---|
| **Pórtico** (*gantry*) | Toda la grúa sobre rieles, a lo largo del muelle | X |
| **Carro** (*trolley*) | El carro sobre la pluma, entre barco y muelle | Z (negativo = mar) |
| **Izaje** (*hoist*) | Sube y baja el spreader con cables | Longitud de cable |

Lo difícil del trabajo real es el **balanceo**: la carga cuelga de cables, así que cada vez que el
carro acelera o frena, el contenedor oscila como un péndulo. Un buen operador aprende a anticipar y
cancelar ese balanceo. Por eso el núcleo del simulador es un péndulo bien hecho; todo lo demás está a
su alrededor.

> El repositorio se llama `mini-sts-godot`: STS es justamente la sigla de este tipo de grúa.

---

## 1. Motor, lenguaje y renderizador

**Decisión:** Godot 4.4, GDScript con tipos estáticos y el renderizador *Compatibility* (OpenGL).

**Por qué:**
- **Godot** es ligero y gratuito, y abre el proyecto en segundos. Todo el proyecto es texto, así que
  se versiona bien en Git.
- **GDScript** en lugar de C#: no requiere instalar .NET y se ejecuta igual en cualquier PC del
  laboratorio. Los tipos estáticos (`var x: float`, `-> Vector3`) dan errores en el editor antes de
  ejecutar y hacen el código más fácil de portar a C# o C++ si el proyecto real lo pide.
- **Compatibility** en lugar de Forward+: funciona en computadoras modestas y permite exportar a web.
  Para la versión final inmersiva convendría Forward+ (mejores sombras e iluminación); es un cambio
  de una línea en `project.godot`.

**Alternativa descartada:** Unreal Engine. Da más calidad visual, pero para un prototipo de física
y control el ciclo de prueba es mucho más lento.

---

## 2. La regla más importante: separar simulación y dibujo

```
 Entrada (teclado, mando, palancas UDP)
            │  comandos -1..1
            ▼
 ┌─────────────────────────────┐
 │ scripts/sim  (sin gráficos) │   CraneGame → CraneModel → AxisDrive ×3
 │ física + reglas             │                          → RopeLoad (péndulo)
 └─────────────────────────────┘                          → Yard (pilas y superficies)
            │  estado (posiciones, velocidades, contacto)
            ▼
 ┌─────────────────────────────┐
 │ scripts/world, scripts/ui   │   CraneView, ContainersView, CameraRig, Hud
 │ sólo dibuja                 │
 └─────────────────────────────┘
```

Todo lo que está en `scripts/sim/` hereda de `RefCounted`, no de `Node`: son clases de datos puros
que no saben que existe una pantalla. La vista sólo **lee** su estado y lo copia a nodos 3D.

**Por qué:**
1. **Se puede probar sin abrir el juego.** `tests/run_tests.gd` crea una grúa y la simula miles de
   pasos en milisegundos.
2. **Es determinista.** La misma entrada produce exactamente el mismo resultado, lo que permite
   repetir un ejercicio y comparar operadores.
3. **Se puede cambiar la vista sin tocar la física**, por ejemplo usar modelos de Blender, pasar a
   realidad virtual o mover la física a otro motor.
4. **El hardware se integra en un solo punto.** Las palancas reales sólo producen tres números
   entre -1 y 1, igual que el teclado.

---

## 3. Unidades y medidas reales

Todo está en **metros, segundos y grados**. Las medidas son reales o cercanas:

- Contenedor ISO de 20 pies: 6.06 × 2.44 × 2.59 m (`Yard.CONTAINER_*`).
- Cables cuelgan desde 35 m de altura; cable de 3 a 41 m.
- Velocidades: pórtico 1.5 m/s, carro 3 m/s, izaje 1.8 m/s vacío y 1.2 m/s cargado.

**Por qué:** en un simulador de entrenamiento las sensaciones deben corresponder a la realidad. Si
el contenedor midiera "1 unidad", el periodo del péndulo y las velocidades no significarían nada.

---

## 4. Los motores: `AxisDrive` (`scripts/sim/axis_drive.gd`)

Una palanca real no fija la posición: fija una **velocidad deseada**. El variador del motor lleva la
velocidad real hacia ese valor sin superar una aceleración máxima.

```gdscript
var target := clampf(command, -1.0, 1.0) * max_speed
velocity = move_toward(velocity, target, max_acceleration * dt)
position += velocity * dt
```

**Frenado antes del final de carrera.** Si el carro va a 3 m/s y quedan 2 m de riel, no le da tiempo
a frenar. Para evitarlo, la velocidad permitida se limita a la que todavía deja detenerse:

    v² = 2·a·d   →   v_max = √(2·a·d)

donde `d` es la distancia al final del riel. Así el eje frena solo al acercarse al límite, como hacen
los interruptores de final de carrera reales. La prueba `test_drive_stops_at_travel_limit` comprueba
que nunca se pasa.

**Por qué importa la aceleración limitada:** es lo que genera el balanceo. Si la velocidad cambiara
de golpe, la carga daría un tirón instantáneo y no se parecería a la realidad.

---

## 5. El péndulo: `RopeLoad` (`scripts/sim/rope_load.gd`)

### Modelo

La carga (spreader + contenedor) es una **masa puntual** colgada de un cable que:
- **no se estira**: la distancia al carro nunca supera la longitud del cable;
- **sí se afloja**: si la carga está apoyada, el cable puede quedar flojo.

### Integración de Verlet

En lugar de guardar la velocidad, Verlet guarda la **posición anterior**. La velocidad está implícita
en `posición - posición_anterior`:

```gdscript
var displacement := position - previous
previous = position
position += displacement * (1.0 - damping * dt) + gravity * dt * dt
```

Después se aplica el cable: si la carga quedó más lejos que la longitud del cable, se proyecta de
vuelta sobre la esfera de radio L:

```gdscript
if distance > length:
    position = anchor + offset / distance * length
```

**Por qué Verlet y no las físicas de Godot (`RigidBody3D` + `PinJoint`):**
1. **Restricciones simples.** Con Verlet, una restricción es "mover el punto"; la velocidad se
   corrige sola. Con cuerpos rígidos, un cable que se afloja y se tensa es muy difícil de ajustar y
   suele vibrar.
2. **Longitud variable.** Al subir o bajar, el cable cambia de longitud cada paso; en Verlet basta con
   usar la nueva longitud.
3. **Control total y determinismo.** Sabemos exactamente qué hace cada línea, y el resultado no
   depende de la versión del motor de físicas.
4. **El balanceo sale solo.** Nunca se programa "si el carro acelera, inclinar la carga": se mueve el
   punto de anclaje y la física hace el resto.

### Paso fijo de 240 Hz

`CraneModel.step()` acumula el tiempo del cuadro y lo consume en pasos fijos de 1/240 s:

```gdscript
_accumulator += dt
while _accumulator >= SUBSTEP:
    _accumulator -= SUBSTEP
    _substep(...)
```

**Por qué:** con un paso variable, una PC lenta simularía distinto que una rápida. Con paso fijo el
resultado es idéntico en cualquier máquina. Se eligen 240 Hz porque el péndulo y los contactos se ven
estables y siguen siendo baratos de calcular (sólo una masa puntual).

### Validación con la teoría

Un péndulo de longitud L oscila con periodo T = 2π·√(L/g). Para L = 20 m, T ≈ 8.97 s. La prueba
`test_pendulum_period_matches_theory` suelta la carga con 3° de inclinación, mide el periodo y
exige un error menor al 2 %. **Ésta es la prueba que demuestra que la física es correcta y no sólo
"parece" correcta.**

### Amortiguamiento

`damping = 0.04` (1/s) representa el aire y la fricción interna del cable. Es bajo a propósito: si el
balanceo se apagara solo y rápido, el operador no tendría que aprender a controlarlo.

---

## 6. Contactos: apoyarse y chocar (`CraneModel._resolve_contacts`)

### Decisión: alturas en lugar de un motor de colisiones

El escenario de un puerto es muy regular: todo son pilas de cajas sobre superficies planas. Por eso
`Yard.surface_height(área)` responde una sola pregunta: *¿cuál es la superficie más alta debajo de
esta huella?* Considera el muelle, la cubierta del barco y la cima de cada pila de contenedores.

Con esa función se resuelven dos casos:

1. **Apoyo vertical.** Si la base de la carga quedó por debajo de la superficie, se sube hasta
   tocarla y se anula la velocidad. Si bajaba a más de 0.7 m/s, cuenta como **apoyo brusco**.
2. **Choque lateral.** Si al moverse en horizontal la huella entra en algo **más de 0.3 m más alto**
   que la base de la carga, no es un apoyo: es un golpe contra una pared. Se deshace el movimiento en
   el eje que choca (primero se prueba conservar X y luego Z, para que la carga pueda "deslizar" por la
   pared) y, si iba a más de 0.2 m/s, cuenta como **golpe**.

El umbral de 0.3 m (`STEP_TOLERANCE`) separa ambos casos. Sin él, un contenedor que roza el borde de
una pila "treparía" a ella mágicamente.

**Anular velocidad en Verlet:** como la velocidad es `position - previous`, basta con igualar
`previous` a `position` en el eje que se quiere frenar.

**Por qué no `CollisionShape3D` y el motor de físicas:** para cajas alineadas a los ejes, esta solución
tiene unas 30 líneas, es exacta y se puede probar. El costo es que no hay rotación de la carga ni
choques con la estructura de la grúa (ver "Limitaciones").

---

## 7. Seguridad: cable flojo y twistlocks

### Freno por cable flojo

Si la carga ya está apoyada y el operador sigue bajando, el cable se acumula y en la realidad puede
salirse de las poleas. Las grúas reales tienen un detector que frena el izaje. En el simulador:

```gdscript
if slack() > SLACK_LIMIT and hoist.velocity >= 0.0:
    hoist.brake()
```

### Twistlocks

Los twistlocks son los cuatro pernos giratorios del spreader que se meten en las esquinas del
contenedor. Sólo pueden cerrar si:
- el spreader está **apoyado** (no colgando),
- está **alineado** con la pila: ±0.30 m en X y ±0.20 m en Z (las guías mecánicas corrigen hasta ahí),
- su base está a menos de 0.15 m del techo del contenedor.

Para abrir con carga se piden las mismas condiciones en el destino. Así es imposible "soltar" un
contenedor en el aire, igual que en la realidad.

---

## 8. El ejercicio: `CraneGame` (`scripts/sim/crane_game.gd`)

Es una máquina de estados con tres fases:

```
PICK (ir por el contenedor) ──cerrar twistlocks──► DELIVER (llevarlo) ──abrir──► siguiente tarea
                                                                       └─ tras 5 tareas ─► DONE
```

- **Semilla fija (`EXERCISE_SEED = 2027`):** el barco y las tareas son siempre los mismos. Para
  entrenamiento esto es intencional: dos operadores hacen exactamente el mismo ejercicio y su
  puntuación se puede comparar.
- **Puntuación por tarea** (sobre 1000): −3 por segundo, −150 por golpe, −75 por apoyo brusco,
  −300 por metro de error de alineación. Los pesos dicen qué importa más: en un puerto un golpe
  cuesta mucho más que unos segundos.
- **Mensajes:** el juego emite una señal `message(texto, nivel)` y el HUD la muestra. La lógica no sabe
  cómo se muestra el mensaje, sólo que ocurrió.

---

## 9. La vista 3D (`scripts/world/`)

- **Toda la geometría se crea por código con cajas** (`MeshUtil.box` y `MeshUtil.beam`). No hay
  modelos externos que descargar ni escenas grandes que mantener. Cada caja se puede reemplazar
  después por un modelo de Blender sin tocar la simulación.
- **Materiales compartidos:** `MeshUtil.material()` reutiliza el mismo material para el mismo color,
  lo que reduce el trabajo de la GPU.
- **Jerarquía de la grúa:** el carro es hijo del pórtico. Al mover el pórtico en X, el carro lo sigue
  solo; al carro sólo hay que darle su Z.
- **Cables:** `MeshUtil.place_beam()` estira una caja de 1 m entre dos puntos construyendo su `Basis`
  a mano. El eje Y de la caja apunta del carro al spreader y se escala por la distancia.
- **Marcadores:** una columna de luz amarilla indica qué contenedor recoger y una verde dónde
  dejarlo. Cada contenedor lleva su número en el techo (visible desde la cabina) y en un costado.
- **Patio de fondo** sólo decorativo, puesto a los lados (|x| > 40 m) para no tapar la cámara.

---

## 10. Cámaras (`scripts/world/camera_rig.gd`)

| Cámara | Para qué sirve | Detalle |
|---|---|---|
| **Cabina** | Lo que ve el operador real | Fija al carro, mirando casi vertical. El balanceo se ve respecto a la ventana, que es lo que el operador aprende a leer. Arriba en pantalla = mar, así **W** mueve la carga hacia arriba en pantalla. |
| **Exterior** | Entender la escena | Orbital, con suavizado exponencial (`1 - exp(-3·dt)`) para no temblar con el balanceo. |
| **Lateral** | Ver la altura al apoyar | Desde el lado de la proa, donde el puente de mando no tapa la vista. |

Detalle de coherencia: en la vista exterior inicial la cámara está del lado de tierra mirando al mar,
así **D** mueve a la derecha y **W** aleja la carga. Los controles se sienten naturales sin explicarlos.

---

## 11. HUD (`scripts/ui/hud.gd`)

Muestra lo que un operador necesita y nada más:
- **Instrumentos:** velocidad y posición de cada eje, cable, altura libre, ángulo de balanceo
  (verde < 1°, amarillo < 3°, rojo después) y estado de los twistlocks.
- **Guía de alineación:** error en cada eje y qué tecla lo corrige; se pone verde (✓) dentro de
  tolerancia.
- **Resumen final** en tabla.

Todos los paneles usan `MOUSE_FILTER_IGNORE` para no bloquear el arrastre de la cámara.

---

## 12. Entrada: teclado, mando y palancas reales (`scripts/input/`)

### Teclado y mando

`InputSetup.register_actions()` define las acciones en código. Así el esquema completo de controles
está en un archivo legible y no escondido en la configuración del proyecto. `Input.get_axis()` da
valores analógicos con el mando y ±1 con teclado. **Shift** reduce al 30 % para maniobras finas,
porque un teclado no es proporcional como una palanca.

### Palancas industriales por UDP

```
Palancas ──► ESP32 / Arduino ──(Wi-Fi o Ethernet, UDP, JSON)──► Simulador (puerto 4242)
```

**Por qué UDP y JSON:**
- **UDP:** para posiciones de palanca sólo importa el dato más reciente. Si se pierde un paquete, el
  siguiente llega 33 ms después; no tiene sentido esperar un reenvío como haría TCP.
- **JSON:** se puede leer a simple vista al depurar (`{"trolley": 0.5}`) y es fácil de generar en un
  ESP32. Si hiciera falta más rendimiento, se cambiaría a un formato binario en un solo archivo.
- **Seguridad (`TIMEOUT_MS = 500`):** si dejan de llegar datos, por ejemplo porque se desconectó el
  cable, las palancas vuelven a cero. Una grúa nunca debe seguir moviéndose porque se perdió la
  comunicación.
- **Botón por flanco:** el botón de twistlocks se detecta al pasar de suelto a pulsado, no mientras
  está pulsado. Así mantenerlo apretado no abre y cierra en bucle.

Las palancas y el teclado se **suman**: un instructor puede intervenir con el teclado mientras el
alumno usa las palancas.

`tools/simular_palancas.py` envía el mismo mensaje que enviaría el ESP32, para probar sin hardware.

---

## 13. Pruebas automáticas (`tests/run_tests.gd`)

Se ejecutan sin ventana (`godot --headless -s tests/run_tests.gd`) y comprueban:

| Prueba | Qué garantiza |
|---|---|
| `test_drive_respects_acceleration` | Los motores respetan aceleración y velocidad máximas |
| `test_drive_stops_at_travel_limit` | Nunca se pasa del final de carrera |
| `test_pendulum_period_matches_theory` | El periodo coincide con 2π·√(L/g) con menos del 2 % de error |
| `test_hanging_load_stays_still` | Sin comandos no hay movimiento fantasma |
| `test_trolley_acceleration_causes_sway` | Acelerar el carro balancea la carga hacia atrás |
| `test_load_cannot_go_through_floor` | La carga no atraviesa el muelle |
| `test_slack_rope_brake` | El freno de cable flojo actúa |
| `test_hard_landing_is_detected` | Bajar rápido penaliza y bajar despacio no |
| `test_side_collision_blocks_motion` | Chocar contra el casco cuenta como golpe y no lo atraviesa |
| `test_lock_requires_alignment` | Desalineado 0.6 m no cierra; 0.1 m sí |
| `test_full_job_flow` | Una tarea completa: recoger, llevar, soltar y puntuar |
| `test_same_seed_same_result` | El simulador es determinista |
| `test_udp_levers` | Lee palancas por red, recorta valores y descarta basura |

**Por qué pruebas en un simulador:** los errores de física son difíciles de ver a ojo. Un péndulo
con el periodo equivocado "se ve bien" y aun así entrenaría mal al operador.

---

## 14. Limitaciones conocidas (dilas tú antes de que te las pregunten)

- **La carga es un punto:** no gira ni se inclina (en grúas reales hay *skew*, *trim* y *list*).
- **Al soltar, el contenedor se coloca exactamente en su posición** aunque estuviera desalineado
  hasta 0.3 m. El error sí se descuenta de la puntuación.
- **Choques simplificados:** la carga no choca con las patas ni con la estructura de la grúa, y los
  choques son totalmente inelásticos (sin rebote).
- **Sin viento, sin oleaje** (el barco no se mueve) **ni retraso hidráulico**.
- **Sin plataforma de movimiento:** `AxisDrive.acceleration` ya calcula las aceleraciones que se le
  enviarían, pero no hay salida implementada.
- **Las palancas físicas no se han probado con hardware real**; sólo con el simulador en Python.
- Gráficos de prototipo (cajas). Probado con renderizado por software; conviene revisarlo en una PC
  con tarjeta gráfica.

---

## 15. Siguientes pasos naturales

1. **Anti-balanceo asistido:** un controlador que ajuste la aceleración del carro para cancelar la
   oscilación (*input shaping*). Es un tema clásico de control.
2. **Viento:** una fuerza horizontal variable sobre la carga en `RopeLoad.integrate()`.
3. **Firmware del ESP32:** leer 3 potenciómetros y un botón y enviar el JSON por Wi-Fi.
4. **Salida a la plataforma de movimiento:** enviar por UDP las aceleraciones de la cabina.
5. **Modelos 3D** de la grúa y el barco hechos en Blender.
6. **Escenarios:** carga de barco (muelle → barco), contenedores de 40 pies y noche con lluvia.

---

## 16. Ejercicios para dominar el código

Hazlos tú mismo. Cada uno toca una parte distinta y te obliga a entenderla:

1. **Cambia `RopeLoad.damping` a 0.0 y a 0.5** y prueba. ¿Por qué un valor alto haría al simulador
   inútil para entrenar?
2. **Añade viento:** en `RopeLoad.integrate()` suma una aceleración `Vector3(0.3, 0, 0)` y observa
   el ángulo de equilibrio. Calcula con trigonometría cuál debería ser y compáralo con el HUD.
3. **Escribe una prueba nueva** que verifique que con cable de 10 m el periodo es ~6.34 s.
4. **Muestra la aceleración del carro en el HUD** usando `model.trolley.acceleration`.
5. **Cambia la semilla** (`EXERCISE_SEED` en `scripts/main.gd`) y verifica que el barco cambia, pero
   siempre igual para la misma semilla.
6. **Reto:** implementa que el contenedor conserve su desalineación al soltarlo en lugar de colocarse
   exacto. Pista: hay que guardar un desplazamiento por contenedor en `Yard`.
