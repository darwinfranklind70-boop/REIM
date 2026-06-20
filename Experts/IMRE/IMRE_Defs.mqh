//+------------------------------------------------------------------+
//|                                                    IMRE_Defs.mqh  |
//|        Metodologia IMRE (Impulso + Retroceso) - Tipos base        |
//|  Definiciones de enums y estructuras compartidas por el sistema.  |
//+------------------------------------------------------------------+
#property copyright "IMRE Methodology"
#property strict

#ifndef __IMRE_DEFS_MQH__
#define __IMRE_DEFS_MQH__

//+------------------------------------------------------------------+
//| Direccion / sesgo de la estructura.                              |
//+------------------------------------------------------------------+
enum ENUM_IMRE_TREND
  {
   TREND_NONE = 0,   // Sin sesgo definido (aun mapeando)
   TREND_BULL = 1,   // Alcista (esperamos compras)
   TREND_BEAR = -1   // Bajista (esperamos ventas)
  };

//+------------------------------------------------------------------+
//| Evento de estructura detectado por CheckBOS_CHoCH().             |
//|  - BOS : Break Of Structure (continuacion en la tendencia)       |
//|  - CHOCH: Change Of Character (cambio de tendencia)              |
//+------------------------------------------------------------------+
enum ENUM_STRUCT_EVENT
  {
   EVENT_NONE       = 0,  // El precio sigue consolidando: no hacer nada
   EVENT_BOS_BULL   = 1,  // Quiebre alcista a favor de tendencia alcista
   EVENT_BOS_BEAR   = 2,  // Quiebre bajista a favor de tendencia bajista
   EVENT_CHOCH_BULL = 3,  // Cambio de caracter a alcista (rompe estructura bajista)
   EVENT_CHOCH_BEAR = 4   // Cambio de caracter a bajista (rompe estructura alcista)
  };

//+------------------------------------------------------------------+
//| Tipo de quiebre: por mecha (rango) o por gap (salto de precio).  |
//+------------------------------------------------------------------+
enum ENUM_BREAK_KIND
  {
   BREAK_NONE = 0,
   BREAK_WICK = 1,   // La mecha (High/Low) cruzo el nivel
   BREAK_GAP  = 2    // Un gap salto el nivel de golpe
  };

//+------------------------------------------------------------------+
//| Punto de swing confirmado o temporal.                            |
//|  - Representa un fractal A (Alto) o B (Bajo) rastreado a mano.    |
//+------------------------------------------------------------------+
struct SwingPoint
  {
   double            price;     // Nivel de precio del swing
   datetime          time;      // Tiempo de la barra que lo formo
   bool              valid;     // true si el punto ya esta inicializado
   ENUM_BREAK_KIND   origin;    // Como nacio (mecha o gap)

   void Reset()
     {
      price  = 0.0;
      time   = 0;
      valid  = false;
      origin = BREAK_NONE;
     }

   void Set(double p, datetime t, ENUM_BREAK_KIND k = BREAK_WICK)
     {
      price  = p;
      time   = t;
      valid  = true;
      origin = k;
     }
  };

//+------------------------------------------------------------------+
//| Resultado completo de una evaluacion de estructura.              |
//+------------------------------------------------------------------+
struct StructResult
  {
   ENUM_STRUCT_EVENT event;     // Evento detectado
   ENUM_BREAK_KIND   kind;      // Mecha o gap
   double            level;     // Nivel que fue roto
   datetime          time;      // Tiempo del quiebre

   void Reset()
     {
      event = EVENT_NONE;
      kind  = BREAK_NONE;
      level = 0.0;
      time  = 0;
     }
  };

//+------------------------------------------------------------------+
//| Etiquetas estructurales de la "N" (para logging / dibujado).     |
//|  A+A = Alto mas Alto (Higher High)                               |
//|  B+A = Bajo mas Alto (Higher Low)                                |
//|  A+B = Alto mas Bajo (Lower High)                                |
//|  B+B = Bajo mas Bajo (Lower Low)                                 |
//+------------------------------------------------------------------+
enum ENUM_FRACTAL_LABEL
  {
   LBL_AA,   // Alto mas Alto
   LBL_BA,   // Bajo mas Alto
   LBL_AB,   // Alto mas Bajo
   LBL_BB    // Bajo mas Bajo
  };

//+------------------------------------------------------------------+
//| Constantes de niveles Fibonacci de la metodologia (en %).        |
//+------------------------------------------------------------------+
#define IMRE_FIB_DECISIONAL_START   0.70   // Zona Decisional inicio (70)
#define IMRE_FIB_DECISIONAL_END     0.80   // Zona Decisional fin    (80)
#define IMRE_FIB_EXTREMO_START      0.90   // Zona Extremo inicio    (90)
#define IMRE_FIB_EXTREMO_END        1.05   // Zona Extremo fin       (105)

#define IMRE_FIB_ENTRY              0.70   // Entrada principal (limit)
#define IMRE_FIB_SL_PRIMARY         0.90   // SL de la entrada principal
#define IMRE_FIB_REENTRY            0.90   // Reentrada (sweep/barrido)
#define IMRE_FIB_SL_FINAL           1.05   // SL definitivo de la reentrada

#endif // __IMRE_DEFS_MQH__
//+------------------------------------------------------------------+
