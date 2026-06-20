//+------------------------------------------------------------------+
//|                                                      IMRE_EA.mq5  |
//|              Expert Advisor - Metodologia IMRE                    |
//|                  (Impulso + Retroceso)                            |
//|                                                                   |
//|  Acción del precio PURA. PROHIBIDO iFractals, ZigZag, Pivots o    |
//|  cualquier indicador de Bill Williams. Toda la estructura se      |
//|  rastrea vela a vela mediante variables de estado.                |
//|                                                                   |
//|  FLUJO MULTI-TEMPORAL:                                            |
//|   Fase 1 (M15): mapear el fractal activo (A/B) + apoyo H1/H4.     |
//|   Fase 2 (M15/M5): trazar Fibonacci, zonas 70-80 y 90-105;        |
//|                    refinar picos con High/Low de M5.              |
//|   Fase 3 (M1): esperar que el precio entre a la zona del M15.     |
//|   Fase 4 (M1): exigir CHoCH en M1 a favor del M15 -> sincronia.   |
//|   Ejecucion: Fibonacci interno del mini-impulso M1, entrada 70.   |
//+------------------------------------------------------------------+
#property copyright "IMRE Methodology"
#property version   "1.00"
#property strict

#include "IMRE_Defs.mqh"
#include "CStructureEngine.mqh"
#include "CFibZones.mqh"
#include "CTradeManager.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Temporalidades ==="
input ENUM_TIMEFRAMES InpTF_Map      = PERIOD_M15;  // TF de mapeo (fractal principal)
input ENUM_TIMEFRAMES InpTF_Refine   = PERIOD_M5;   // TF de refinamiento de picos
input ENUM_TIMEFRAMES InpTF_Trigger  = PERIOD_M1;   // TF de sincronizacion / gatillo
input ENUM_TIMEFRAMES InpTF_BiasA    = PERIOD_H1;   // Apoyo direccional 1
input ENUM_TIMEFRAMES InpTF_BiasB    = PERIOD_H4;   // Apoyo direccional 2

input group "=== Estructura ==="
input int    InpSeedLookback   = 30;     // Barras para sembrar el fractal inicial
input double InpMarubozuTol    = 1.0;    // Tolerancia marubozu (puntos)
input bool   InpUseHTFBias     = true;   // Apoyarse en H1/H4 ante ruido en M15

input group "=== Zona y entrada ==="
input bool   InpRequireZone    = true;   // Exigir que M1 entre en zona 70-105 de M15
input bool   InpRequireCHoCH_M1= true;   // Exigir CHoCH en M1 antes de entrar

input group "=== Riesgo / TP ==="
input double InpRiskPercent    = 1.0;    // % de balance por idea
input double InpRR_TP1         = 3.0;    // Ratio TP1 (seguridad)
input double InpRR_TP2         = 10.0;   // Ratio TP2 (runner)
input double InpSplitTP1       = 0.5;    // Fraccion de volumen a TP1
input double InpSplitTP2       = 0.3;    // Fraccion de volumen a TP2
input ulong  InpMagic          = 20240601; // Magic number

input group "=== Visual / Log ==="
input bool   InpVerbose        = true;   // Logs detallados
input bool   InpDrawObjects    = true;   // Dibujar zonas en el grafico

//+------------------------------------------------------------------+
//| Estado de la maquina de fases                                    |
//+------------------------------------------------------------------+
enum ENUM_PHASE
  {
   PHASE_MAP,        // Fase 1: mapeando M15
   PHASE_ZONE,       // Fase 2/3: esperando que M1 entre a zona
   PHASE_WAIT_CHOCH, // Fase 4: esperando CHoCH en M1
   PHASE_EXECUTE,    // Ejecucion lista
   PHASE_MANAGE      // Gestionando operacion viva
  };

//+------------------------------------------------------------------+
//| Globales                                                         |
//+------------------------------------------------------------------+
CStructureEngine g_eng_map;     // Motor M15 (mapeo)
CStructureEngine g_eng_refine;  // Motor M5  (refinamiento)
CStructureEngine g_eng_trig;    // Motor M1  (gatillo)
CStructureEngine g_eng_h1;      // Motor H1  (apoyo)
CStructureEngine g_eng_h4;      // Motor H4  (apoyo)

CFibZones        g_fibM15;      // Fibonacci del impulso M15
CFibZones        g_fibM1;       // Fibonacci del mini-impulso M1
CTradeManager    g_tm;          // Gestor de ordenes

ENUM_PHASE       g_phase = PHASE_MAP;
ENUM_IMRE_TREND  g_bias  = TREND_NONE; // sesgo operativo (del M15)

datetime         g_lastBarM15 = 0;
datetime         g_lastBarM1  = 0;

string           g_prefix = "IMRE_";

//+------------------------------------------------------------------+
//| Utilidades                                                       |
//+------------------------------------------------------------------+
void Log(string msg)
  {
   if(InpVerbose) Print("IMRE | ", msg);
  }

bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &store)
  {
   datetime t = iTime(_Symbol, tf, 0);
   if(t != store)
     {
      store = t;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Confirmacion direccional con HTF (H1/H4) ante ruido en M15.      |
//|  Devuelve true si H1 y H4 NO contradicen el sesgo del M15.       |
//+------------------------------------------------------------------+
bool HTFAgrees(ENUM_IMRE_TREND m15bias)
  {
   if(!InpUseHTFBias)
      return true;
   ENUM_IMRE_TREND h1 = g_eng_h1.Trend();
   ENUM_IMRE_TREND h4 = g_eng_h4.Trend();
   // Si alguno tiene sesgo opuesto fuerte, lo consideramos ruido/contra.
   if(h1 != TREND_NONE && h1 != m15bias && h4 != TREND_NONE && h4 != m15bias)
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Dibuja una linea horizontal de referencia.                       |
//+------------------------------------------------------------------+
void DrawHLine(string name, double price, color clr, string text)
  {
   if(!InpDrawObjects) return;
   string obj = g_prefix + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, obj, OBJPROP_PRICE, price);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
  }

void ClearObjects()
  {
   ObjectsDeleteAll(0, g_prefix);
  }

//+------------------------------------------------------------------+
//| Refina un nivel de pico/valle con los High/Low exactos de M5.    |
//|  Busca en las ultimas N barras de M5 el extremo mas cercano.     |
//+------------------------------------------------------------------+
double RefinePeakWithM5(double approxLevel, bool wantHigh, int lookback = 24)
  {
   int bars = Bars(_Symbol, InpTF_Refine);
   if(bars < lookback + 2)
      return approxLevel;

   double best = approxLevel;
   double bestDist = DBL_MAX;
   for(int sh = 1; sh <= lookback; sh++)
     {
      double v = wantHigh ? iHigh(_Symbol, InpTF_Refine, sh)
                          : iLow (_Symbol, InpTF_Refine, sh);
      double d = MathAbs(v - approxLevel);
      if(d < bestDist)
        {
         bestDist = d;
         best     = v;
        }
     }
   return best;
  }

//+------------------------------------------------------------------+
//| FASE 1 + 2: mapeo M15 y construccion de zonas Fibonacci.         |
//+------------------------------------------------------------------+
void BuildM15Zones()
  {
   double origin, target;
   if(!g_eng_map.GetActiveImpulse(origin, target))
      return;

   // Fase 2: refinar picos con M5 para maxima precision.
   bool bull = (target >= origin);
   double refTarget = RefinePeakWithM5(target, bull);          // punta
   double refOrigin = RefinePeakWithM5(origin, !bull);         // base

   g_fibM15.SetImpulse(refOrigin, refTarget);

   if(InpDrawObjects)
     {
      DrawHLine("M15_70",  g_fibM15.DecisionalNear(), clrDodgerBlue, "M15 70");
      DrawHLine("M15_80",  g_fibM15.DecisionalFar(),  clrDodgerBlue, "M15 80");
      DrawHLine("M15_90",  g_fibM15.ExtremoNear(),    clrOrange,     "M15 90");
      DrawHLine("M15_105", g_fibM15.ExtremoFar(),     clrRed,        "M15 105");
      DrawHLine("M15_TGT", g_eng_map.StructuralTarget(), clrLime,    "M15 A+A/B+B");
     }
  }

//+------------------------------------------------------------------+
//| FASE 3: el precio (M1) esta dentro de la zona 70-105 del M15?    |
//+------------------------------------------------------------------+
bool PriceInM15Zone()
  {
   if(!InpRequireZone)
      return true;
   if(!g_fibM15.IsValid())
      return false;
   double price = iClose(_Symbol, InpTF_Trigger, 0);
   return g_fibM15.InWorkingZone(price);
  }

//+------------------------------------------------------------------+
//| FASE 4: CHoCH en M1 a favor del sesgo del M15.                   |
//|  Si M15 es alcista, M1 venia cayendo (A+B/B+B) y el giro ocurre  |
//|  cuando M1 rompe al alza su ultimo A+B -> sincronia alcista.     |
//+------------------------------------------------------------------+
bool CHoCH_M1_Aligned(ENUM_IMRE_TREND m15bias)
  {
   StructResult r = g_eng_trig.Update();
   if(r.event == EVENT_NONE)
      return false;

   if(!InpRequireCHoCH_M1)
     {
      // Sin exigencia estricta: basta un BOS/CHoCH a favor.
      if(m15bias == TREND_BULL && (r.event == EVENT_CHOCH_BULL || r.event == EVENT_BOS_BULL))
         return true;
      if(m15bias == TREND_BEAR && (r.event == EVENT_CHOCH_BEAR || r.event == EVENT_BOS_BEAR))
         return true;
      return false;
     }

   if(m15bias == TREND_BULL && r.event == EVENT_CHOCH_BULL)
     {
      Log("CHoCH alcista en M1 confirmado. M1 y M15 sincronizados al alza.");
      return true;
     }
   if(m15bias == TREND_BEAR && r.event == EVENT_CHOCH_BEAR)
     {
      Log("CHoCH bajista en M1 confirmado. M1 y M15 sincronizados a la baja.");
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| EJECUCION: construir y colocar el setup con el mini-impulso M1.  |
//+------------------------------------------------------------------+
bool ExecuteSetup(ENUM_IMRE_TREND bias)
  {
   // Fibonacci interno al nuevo mini-impulso nacido del CHoCH en M1.
   double o, t;
   if(!g_eng_trig.GetActiveImpulse(o, t))
     {
      Log("No hay impulso M1 valido para ejecutar.");
      return false;
     }
   g_fibM1.SetImpulse(o, t);

   ImreSetup s; s.Reset();
   s.isBull       = (bias == TREND_BULL);
   s.entry        = g_fibM1.EntryLevel();   // 70 del mini-impulso M1
   s.slPrimary    = g_fibM1.SLPrimary();    // 90
   s.reentry      = g_fibM1.ReentryLevel(); // 90
   s.slFinal      = g_fibM1.SLFinal();      // 105
   s.structuralTP = g_eng_map.StructuralTarget(); // A+A/B+B del M15
   s.created      = TimeCurrent();

   if(InpDrawObjects)
     {
      DrawHLine("M1_ENTRY", s.entry,     clrAqua,   "M1 Entry 70");
      DrawHLine("M1_SL",    s.slPrimary, clrMagenta,"M1 SL 90");
      DrawHLine("M1_SLF",   s.slFinal,   clrRed,    "M1 SL 105");
     }

   bool ok = g_tm.PlaceSetup(s);
   if(ok)
      Log(StringFormat("Setup %s colocado. Entry=%.5f SL=%.5f TP_estructural=%.5f",
                       (s.isBull ? "COMPRA" : "VENTA"), s.entry, s.slPrimary, s.structuralTP));
   return ok;
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_eng_map.Init(_Symbol, InpTF_Map,     InpSeedLookback, InpMarubozuTol);
   g_eng_refine.Init(_Symbol, InpTF_Refine, InpSeedLookback, InpMarubozuTol);
   g_eng_trig.Init(_Symbol, InpTF_Trigger, InpSeedLookback, InpMarubozuTol);
   g_eng_h1.Init(_Symbol, InpTF_BiasA,    InpSeedLookback, InpMarubozuTol);
   g_eng_h4.Init(_Symbol, InpTF_BiasB,    InpSeedLookback, InpMarubozuTol);

   g_tm.Init(_Symbol, InpMagic, InpRiskPercent, InpRR_TP1, InpRR_TP2, InpSplitTP1, InpSplitTP2);

   g_phase = PHASE_MAP;
   g_bias  = TREND_NONE;

   Log("EA IMRE inicializado. Esperando mapeo de estructura en " + EnumToString(InpTF_Map));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ClearObjects();
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1) Actualizar motores de estructura cuando cierra una barra nueva.
   bool newM15 = IsNewBar(InpTF_Map, g_lastBarM15);
   bool newM1  = IsNewBar(InpTF_Trigger, g_lastBarM1);

   if(newM15)
     {
      g_eng_map.Update();
      g_eng_refine.Update();
      g_eng_h1.Update();
      g_eng_h4.Update();
     }

   // 2) Gestion de operaciones vivas SIEMPRE tiene prioridad.
   if(g_tm.CountPositions() > 0)
     {
      g_tm.ManageOpenPositions();
      g_tm.ManageReentry();
      g_phase = PHASE_MANAGE;
      return;
     }

   // 3) Maquina de fases.
   switch(g_phase)
     {
      //--- FASE 1+2: mapeo M15 + zonas -------------------------------
      case PHASE_MAP:
        {
         if(!g_eng_map.IsReady())
            return;

         ENUM_IMRE_TREND m15 = g_eng_map.Trend();
         if(m15 == TREND_NONE)
            return;

         if(!HTFAgrees(m15))
           {
            Log("Ruido en M15: H1/H4 contradicen el sesgo. Esperando.");
            return;
           }

         g_bias = m15;
         BuildM15Zones();
         if(g_fibM15.IsValid())
           {
            Log("Fase 1/2 OK. Sesgo M15=" + g_eng_map.TrendText() + ". Zonas trazadas. Esperando precio en zona.");
            g_phase = PHASE_ZONE;
           }
         break;
        }

      //--- FASE 3: esperar precio dentro de la zona 70-105 -----------
      case PHASE_ZONE:
        {
         // Re-mapear si el M15 cambio de estructura.
         ENUM_IMRE_TREND m15 = g_eng_map.Trend();
         if(m15 != g_bias)
           {
            Log("La estructura M15 cambio. Re-mapeando.");
            g_phase = PHASE_MAP;
            return;
           }
         if(newM15)
            BuildM15Zones();

         if(PriceInM15Zone())
           {
            Log("Fase 3 OK. Precio dentro de zona 70-105 del M15. Esperando CHoCH en M1.");
            g_phase = PHASE_WAIT_CHOCH;
           }
         break;
        }

      //--- FASE 4: CHoCH en M1 alineado ------------------------------
      case PHASE_WAIT_CHOCH:
        {
         // Si el precio salio de la zona, volver a esperar zona.
         if(InpRequireZone && !PriceInM15Zone())
           {
            g_phase = PHASE_ZONE;
            return;
           }
         if(!newM1)
            return;

         if(CHoCH_M1_Aligned(g_bias))
           {
            g_phase = PHASE_EXECUTE;
           }
         break;
        }

      //--- EJECUCION -------------------------------------------------
      case PHASE_EXECUTE:
        {
         if(ExecuteSetup(g_bias))
            g_phase = PHASE_MANAGE;
         else
            g_phase = PHASE_WAIT_CHOCH; // reintentar si fallo
         break;
        }

      //--- GESTION ---------------------------------------------------
      case PHASE_MANAGE:
        {
         g_tm.ManageReentry();
         g_tm.ManageOpenPositions();
         // Si ya no hay exposicion, reiniciar el ciclo.
         if(!g_tm.HasExposure())
           {
            Log("Ciclo cerrado. Reiniciando mapeo.");
            g_tm.CancelPending();
            g_phase = PHASE_MAP;
           }
         break;
        }
     }
  }
//+------------------------------------------------------------------+
