//+------------------------------------------------------------------+
//|                                                   CFibZones.mqh   |
//|   Metodologia IMRE - Trazado de Fibonacci sobre el impulso        |
//|                                                                   |
//|   Convencion: el 0% esta en el INICIO del impulso y el 100% en    |
//|   el final (la punta). El retroceso se mide hacia el 0%, por lo   |
//|   que las zonas profundas (70-105) quedan cerca del origen.       |
//+------------------------------------------------------------------+
#property strict

#ifndef __IMRE_FIBZONES_MQH__
#define __IMRE_FIBZONES_MQH__

#include "IMRE_Defs.mqh"

//+------------------------------------------------------------------+
//| CFibZones                                                        |
//|  Calcula niveles de retroceso sobre un impulso (origin->target). |
//|  Para IMRE el retroceso se mide desde el final del impulso        |
//|  (100%) de regreso al origen (0%). Asi:                          |
//|    nivel(r) = target - r*(target-origin)  [impulso alcista]      |
//|    nivel(r) = target + r*(origin-target)  [impulso bajista]      |
//|  En ambos casos r=0 -> target (punta), r=1 -> origin (base).     |
//+------------------------------------------------------------------+
class CFibZones
  {
private:
   double            m_origin;   // 0% logico del retroceso? -> base del impulso
   double            m_target;   // punta del impulso
   bool              m_bull;     // true si el impulso es alcista
   bool              m_valid;

public:
                     CFibZones() { Reset(); }

   void              Reset()
     {
      m_origin = 0.0; m_target = 0.0; m_bull = true; m_valid = false;
     }

   //--- Define el impulso. origin = base, target = punta.
   void              SetImpulse(double origin, double target)
     {
      m_origin = origin;
      m_target = target;
      m_bull   = (target >= origin);
      m_valid  = (origin != target);
     }

   bool              IsValid() const { return m_valid; }
   bool              IsBull()  const { return m_bull;  }
   double            Origin()  const { return m_origin; }
   double            Target()  const { return m_target; }
   double            Range()   const { return MathAbs(m_target - m_origin); }

   //--- Devuelve el precio de un nivel de retroceso 'r' (0..1.05).
   //    r = 0   -> punta del impulso (target)
   //    r = 1   -> base del impulso  (origin)
   //    r > 1   -> extension mas alla de la base (zona extremo 105)
   double            Level(double r) const
     {
      if(!m_valid)
         return 0.0;
      double rng = (m_target - m_origin); // con signo
      return m_target - r * rng;
     }

   //--- Zona Decisional (70 a 80).
   double            DecisionalNear() const { return Level(IMRE_FIB_DECISIONAL_START); } // 70
   double            DecisionalFar()  const { return Level(IMRE_FIB_DECISIONAL_END);   } // 80

   //--- Zona Extremo (90 a 105).
   double            ExtremoNear()    const { return Level(IMRE_FIB_EXTREMO_START); }    // 90
   double            ExtremoFar()     const { return Level(IMRE_FIB_EXTREMO_END);   }    // 105

   //--- Niveles operativos.
   double            EntryLevel()     const { return Level(IMRE_FIB_ENTRY);       }      // 70
   double            SLPrimary()      const { return Level(IMRE_FIB_SL_PRIMARY);  }      // 90
   double            ReentryLevel()   const { return Level(IMRE_FIB_REENTRY);     }      // 90
   double            SLFinal()        const { return Level(IMRE_FIB_SL_FINAL);    }      // 105

   //--- True si 'price' esta dentro de la zona operativa 70..105.
   bool              InWorkingZone(double price) const
     {
      if(!m_valid) return false;
      double a = Level(IMRE_FIB_DECISIONAL_START); // 70
      double b = Level(IMRE_FIB_EXTREMO_END);      // 105
      double lo = MathMin(a, b);
      double hi = MathMax(a, b);
      return (price >= lo && price <= hi);
     }

   //--- True si 'price' esta dentro de la zona Decisional 70..80.
   bool              InDecisionalZone(double price) const
     {
      if(!m_valid) return false;
      double a = Level(IMRE_FIB_DECISIONAL_START);
      double b = Level(IMRE_FIB_DECISIONAL_END);
      double lo = MathMin(a, b), hi = MathMax(a, b);
      return (price >= lo && price <= hi);
     }

   //--- True si 'price' esta dentro de la zona Extremo 90..105.
   bool              InExtremoZone(double price) const
     {
      if(!m_valid) return false;
      double a = Level(IMRE_FIB_EXTREMO_START);
      double b = Level(IMRE_FIB_EXTREMO_END);
      double lo = MathMin(a, b), hi = MathMax(a, b);
      return (price >= lo && price <= hi);
     }

   //--- Calcula un objetivo por Ratio Riesgo/Beneficio dado entry y SL.
   //    rr = 3.0 -> TP a 1:3.  Respeta la direccion (bull/bear).
   static double     TargetByRR(double entry, double sl, double rr, bool isBull)
     {
      double risk = MathAbs(entry - sl);
      return isBull ? (entry + rr * risk) : (entry - rr * risk);
     }
  };

#endif // __IMRE_FIBZONES_MQH__
//+------------------------------------------------------------------+
