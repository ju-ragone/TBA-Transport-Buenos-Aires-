# Simulador de Colectivos de Buenos Aires en Godot 4

Esto arrancó como una maqueta y terminó siendo un proyecto que fui armando a los ponchazos tirándole prompts a una IA. La premisa era bastante simple: tener el mapa de Capital Federal de fondo, tirar recorridos de colectivos, meter el Premetro con sus rieles y catenaria, semáforos que corten como corresponde, estaciones de Metrobús y simular la demanda de pasajeros según la hora pico.

---

## Aclaraciones y Estado del Proyecto
Subo esto principalmente como backup para no perder lo que se fue programando.

No esperes un juego terminado ni pulido: no sé programar de forma profesional en Godot y muchas cosas se resolvieron atadas con alambre. Vas a encontrar bugs raros, coches que a veces se enciman, cálculos matemáticos que fallan o cosas que se rompen si las tocás de más.

Si cazás algo de GDScript y tenés ganas de clonarlo, meterle mano, emprolijar la arquitectura, separar los scripts o sumar mecánicas porque te copó la idea, mandale para adelante. Cualquier pull request, fork o mejora se agradece una banda.

---

## Controles y Atajos
* **Clic Izquierdo:** Trazar calles, colocar paradas, confirmar edificios y marcar esquinas de las zonas RCI.
* **D / Shift + D:** Previsualizar y colocar Depósito de Colectivos o Depósito de Premetro.
* **R:** Rotar la estructura en previsualización (45 grados por toque) o abrir el selector de Zonas RCI.
* **M:** Alternar modo de transporte activo entre Colectivo urbano y Premetro Materfer.
* **T:** Previsualizar y colocar estación de Metrobús (conecta hasta 6 líneas).
* **G:** Colocar pórtico vial de Salida al Conurbano (los coches salen de Capital un rato y vuelven).
* **V:** Modo desdoblar en 1 mano (permite abrir la traza en calle de ida y calle paralela de vuelta).
* **Shift + Clic (o tecla P):** Colocar poste de Parada estilo CABA sobre una línea existente.
* **S:** Activar modo Semáforo (coloca cruce de 4 postes amarillos con fases de 3 luces).
* **Espacio / Enter:** Inaugurar la línea que estás dibujando o cerrar el polígono de una zona RCI.
* **E + Clic:** Editar número de línea, letra de ramal, texto de la cartelera y tiempo de viaje en provincia.
* **I + Clic:** Inspeccionar y rotar depósitos o paradas con un slider (360 grados), o editar los textos del pórtico de autopista.
* **L:** Abrir la lista general de líneas para ver la flota, resaltarlas en el mapa o seguirlas con la cámara.
* **Z / C:** Deshacer último punto marcado o cancelar el trazado en curso.
* **K + Clic:** Borrar semáforo de una esquina.
* **J + Clic:** Borrar depósitos, estaciones de Metrobús, paradas o pórticos.
* **X + Clic:** Borrar una línea completa junto con sus colectivos.
* **Clic sobre un Colectivo:** Seguir la unidad con la cámara.
* **Clic Derecho o Rueda (arrastrar):** Orbitar la cámara libremente en 360 grados alrededor del coche o hacer zoom.
* **Escape:** Liberar la cámara a vista cenital libre o cancelar la colocación de un edificio.

---

## Cómo Funciona el Juego
* **Salida desde cabecera:** Toda línea nueva tiene que arrancar obligatoriamente adentro de un depósito. Hacés clic sobre el playón y desde ahí salís a buscar las avenidas.
* **Sentidos de circulación:** El trazado genera dos carriles separados en el asfalto para que las unidades no se choquen de frente. Si una avenida se corta y las manos van por calles paralelas distintas, tocás la **V** para abrir la bifurcación, marcás la ida, tocás la **V** de nuevo para trazar el regreso y cerrás el lazo.
* **Zonas RCI y pasajeros:** Con la tecla **R** podés delimitar zonas de casas, torres, oficinas, comercios o industrias marcando varios puntos para seguir las diagonales del mapa. La población se calcula en base al área y altura estimada de la zona. A la mañana la gente sale de los barrios residenciales, llena las paradas (representadas con personitas donde cada muñeco equivale a 5 personas) y viaja hacia las zonas laborales o comerciales para cumplir su jornada.
* **Carteleras LED:** Al seleccionar cualquier coche podés escribirle lo que quieras en la caja de texto del panel inferior (por ejemplo el número y el destino) y se actualiza en tiempo real en la marquesina ámbar arriba del parabrisas.

---

## Requisitos Técnicos
* Godot Engine 4.2 o 4.3 (versión estándar con soporte para GDScript).
* Renderizador Forward+
* Sisi, eso también fue IA.

---

## Lista de Bugs y Problemas Conocidos
* **Zonas RCI Poligonales:** Si al marcar los puntos del polígono te cruzás de borde o hacés una figura muy extraña, la triangulación geométrica puede fallar y la zona se crea corrupta o no aparece. Conviene hacer formas limpias y sin cruzar las líneas entre sí.
* **Semáforos (Fase y botón "Invertir Fases"):**
  * *El bug crónico:* Al hacer clic en el semáforo para editar sus fases y tocar el botón "🔄 Invertir Fase Ahora", el script de la ventana colapsa y cierra el juego totalmente (crash al escritorio) por un conflicto con el estado interno del temporizador.
  * *Problema de frenado previo:* Aunque se mejoró la distancia, en intersecciones muy transitadas algunos coches pueden llegar a detenerse demasiado justos o rozar el límite de la senda peatonal.
* **Modo Desdoblar 1 Mano (Tecla V):** Es la herramienta más experimental de todas. Si no unís bien los nodos de reencuentro al carril principal o si la geometría del trazado se cruza de forma rara, la curva física puede bugearse. *Recomendación actual:* Para evitar dolores de cabeza, conviene usar el modo estándar de Ida y Vuelta (que es el que anda más sólido), y dejar el desdoblamiento de 1 mano solo para experimentar si te animas a depurarlo.
* **Flota en bucle / Efecto Caravana (Bus Bunching):** A pesar de la segmentación por cantones y la regulación de despacho en cabecera, si dejas correr el juego durante horas sin tocar nada, es probable que los colectivos de una misma línea terminen aglutinándose de a dos o tres formando un trencito.
* **HUD e Indicadores de Opciones:** Como todavía no se integró la barra visual flotante en pantalla que te canta qué modos tenés encendidos, es fácil perderse y olvidarse si tenías activo el modo desdoblar, el semáforo o la zonificación RCI (tené siempre a mano la ayuda con la tecla H).