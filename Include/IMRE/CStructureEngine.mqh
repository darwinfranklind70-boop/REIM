//+------------------------------------------------------------------+
//|                                            CStructureEngine.mqh   |
//|   Metodologia IMRE - Motor de deteccion de estructura PURO        |
//|                                                                   |
//|   PROHIBIDO usar iFractals / ZigZag / Pivot / Bill Williams.      |
//|   La estructura se rastrea vela a vela (OHLC) con variables de    |
//|   estado. Detecta la "forma en N" mediante BOS y CHoCH validando  |
//|   quiebres por MECHA (High/Low) y por GAP (salto de precio).      |
//+------------------------------------------------------------------+
#property strict

#ifndef __IMRE_STRUCTURE_ENGINE_MQH__
#define __IMRE_STRUCTURE_ENGINE_MQH__

#include "IMRE_Defs.mqh"

//+------------------------------------------------------------------+
//| CStructureEngine                                                 |
//|                                                                  |
//|  Mantiene en memoria, para UNA temporalidad concreta:            |
//|   - Ultimo_Alto_Confirmado  (fractal A activo)                   |
//|   - Ultimo_Bajo_Confirmado  (fractal B activo)                   |
//|   - Punto_Extremo_Temporal  (el extremo del retroceso en curso)  |
//|   - Etiquetas A+A, B+A, A+B, B+B y el sesgo actual.              |
//+------------------------------------------------------------------+
class CStructureEngine
  {
private:
   string            m_symbol;        // Simbolo
   ENUM_TIMEFRAMES   m_tf;            // Temporalidad de este motor
   double            m_point;         // _Point del simbolo
   int               m_digits;        // Digitos del simbolo

   ENUM_IMRE_TREND   m_trend;         // Sesgo actual (N alcista / bajista)

   //--- Niveles estructurales confirmados (los limites de la "N")
   SwingPoint        m_lastHigh;      // Ultimo_Alto_Confirmado  (A)
   SwingPoint        m_lastLow;       // Ultimo_Bajo_Confirmado  (B)

   //--- Etiquetas vivas del fractal (resultado de la ultima N)
   SwingPoint        m_AA;            // Alto mas Alto  (Higher High)
   SwingPoint        m_BA;            // Bajo mas Alto  (Higher Low)
   SwingPoint        m_AB;            // Alto mas Bajo  (Lower High)
   SwingPoint        m_BB;            // Bajo mas Bajo  (Lower Low)

   //--- Rastreo silencioso del retroceso (mientras el precio consolida)
   SwingPoint        m_tempLow;       // Extremo bajo del retroceso (para BOS alcista)
   SwingPoint        m_tempHigh;      // Extremo alto del retroceso (para BOS bajista)

   datetime          m_lastProcessed; // Tiempo de la ultima barra procesada
   bool              m_initialized;   // Niveles base ya sembrados

   double            m_marubozuTol;   // Tolerancia (puntos) para considerar marubozu

   //--- Helpers internos -------------------------------------------------
   double            Hi(int sh) const { return iHigh (m_symbol, m_tf, sh); }
   double            Lo(int sh) const { return iLow  (m_symbol, m_tf, sh); }
   double            Op(int sh) const { return iOpen (m_symbol, m_tf, sh); }
   double            Cl(int sh) const { return iClose(m_symbol, m_tf, sh); }
   datetime          Tm(int sh) const { return iTime (m_symbol, m_tf, sh); }

   //--- Determina si la vela es marubozu por arriba (sin mecha superior).
   bool              IsMarubozuTop(int sh) const
     {
      double body = MathMax(Op(sh), Cl(sh));
      return ((Hi(sh) - body) <= m_marubozuTol * m_point);
     }
   //--- Determina si la vela es marubozu por abajo (sin mecha inferior).
   bool              IsMarubozuBottom(int sh) const
     {
      double body = MathMin(Op(sh), Cl(sh));
      return ((body - Lo(sh)) <= m_marubozuTol * m_point);
     }

   //--- Siembra los niveles base con el rango de N barras iniciales.
   void              SeedLevels(int lookback);

public:
                     CStructureEngine();
   void              Init(const string symbol, ENUM_TIMEFRAMES tf, int seed_lookback = 20, double marubozu_tol = 1.0);

   //--- API principal: evalua UNA barra cerrada (shift) y actualiza el estado.
   //    Devuelve el evento de estructura (BOS / CHoCH / NONE).
   StructResult      CheckBOS_CHoCH(int shift);

   //--- Evaluacion intrabar (para gatillos en M1): usa la barra en formacion.
   //    'live_high'/'live_low' son el extremo del precio actual.
   StructResult      CheckBOS_CHoCH_Live(double live_high, double live_low, double live_open, double prev_close, datetime cur_time);

   //--- Procesa todas las barras nuevas desde la ultima vez (uso normal en OnTick).
   StructResult      Update();

   //--- Accesores -------------------------------------------------------
   ENUM_IMRE_TREND   Trend()            const { return m_trend; }
   bool              IsBull()           const { return m_trend == TREND_BULL; }
   bool              IsBear()           const { return m_trend == TREND_BEAR; }
   bool              IsReady()          const { return m_initialized; }

   double            LastHigh()         const { return m_lastHigh.price; }
   double            LastLow()          const { return m_lastLow.price;  }
   SwingPoint        ConfirmedHigh()    const { return m_lastHigh; }
   SwingPoint        ConfirmedLow()     const { return m_lastLow;  }

   //--- Objetivo estructural para TP3 (A+A si alcista, B+B si bajista).
   double            StructuralTarget() const;

   SwingPoint        AA() const { return m_AA; }
   SwingPoint        BA() const { return m_BA; }
   SwingPoint        AB() const { return m_AB; }
   SwingPoint        BB() const { return m_BB; }

   //--- El impulso vigente (origen -> destino) para trazar Fibonacci.
   //    En alcista: desde B+A (low) hasta A+A (high).
   //    En bajista: desde A+B (high) hasta B+B (low).
   bool              GetActiveImpulse(double &origin, double &target) const;

   string            TrendText() const;
  };

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStructureEngine::CStructureEngine()
  {
   m_symbol        = _Symbol;
   m_tf            = PERIOD_M15;
   m_point         = _Point;
   m_digits        = (int)_Digits;
   m_trend         = TREND_NONE;
   m_lastProcessed = 0;
   m_initialized   = false;
   m_marubozuTol   = 1.0;
   m_lastHigh.Reset();
   m_lastLow.Reset();
   m_AA.Reset(); m_BA.Reset(); m_AB.Reset(); m_BB.Reset();
   m_tempLow.Reset();
   m_tempHigh.Reset();
  }

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
void CStructureEngine::Init(const string symbol, ENUM_TIMEFRAMES tf, int seed_lookback, double marubozu_tol)
  {
   m_symbol      = symbol;
   m_tf          = tf;
   m_point       = SymbolInfoDouble(symbol, SYMBOL_POINT);
   m_digits      = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   m_marubozuTol = marubozu_tol;
   m_trend       = TREND_NONE;
   m_initialized = false;
   m_lastProcessed = 0;
   SeedLevels(seed_lookback);
  }

//+------------------------------------------------------------------+
//| SeedLevels                                                       |
//|  Siembra Ultimo_Alto/Bajo_Confirmado con el rango de las         |
//|  ultimas 'lookback' barras cerradas para arrancar el rastreo.    |
//+------------------------------------------------------------------+
void CStructureEngine::SeedLevels(int lookback)
  {
   int bars = Bars(m_symbol, m_tf);
   if(bars < lookback + 2)
      return; // No hay suficiente historia todavia

   double hh = -DBL_MAX, ll = DBL_MAX;
   datetime th = 0, tl = 0;

   // Recorremos barras CERRADAS (shift 1 .. lookback)
   for(int sh = 1; sh <= lookback; sh++)
     {
      double h = Hi(sh);
      double l = Lo(sh);
      if(h > hh) { hh = h; th = Tm(sh); }
      if(l < ll) { ll = l; tl = Tm(sh); }
     }

   m_lastHigh.Set(hh, th, BREAK_WICK);
   m_lastLow.Set(ll, tl, BREAK_WICK);

   // El sesgo inicial se infiere de cual extremo es mas reciente.
   m_trend = (th > tl) ? TREND_BULL : TREND_BEAR;

   // Etiquetas iniciales coherentes con el rango sembrado.
   m_AA = m_lastHigh;
   m_BB = m_lastLow;

   // Inicializamos el rastreo del retroceso desde el extremo confirmado.
   m_tempLow.Set(m_lastHigh.price, m_lastHigh.time, BREAK_WICK);   // empezara a buscar minimos
   m_tempHigh.Set(m_lastLow.price, m_lastLow.time, BREAK_WICK);    // empezara a buscar maximos

   m_lastProcessed = Tm(1);
   m_initialized   = true;
  }

//+------------------------------------------------------------------+
//| CheckBOS_CHoCH                                                   |
//|                                                                  |
//|  Evalua la barra cerrada 'shift'. Logica de la "N":              |
//|                                                                  |
//|  1) Mientras la barra NO rompa ni Ultimo_Alto ni Ultimo_Bajo,    |
//|     el precio consolida: rastreamos silenciosamente el extremo   |
//|     del retroceso (Punto_Extremo_Temporal) y devolvemos NONE.    |
//|                                                                  |
//|  2) Si la MECHA (o un GAP) cruza Ultimo_Alto_Confirmado:         |
//|       -> BOS alcista (si ya alcista) o CHoCH alcista (si bajista)|
//|       -> El temp extremo bajo se BLOQUEA como nuevo B+A.         |
//|       -> El nuevo high de la vela que rompio pasa a ser A+A.     |
//|                                                                  |
//|  3) Simetrico para quiebre del Ultimo_Bajo_Confirmado.           |
//|                                                                  |
//|  Manejo de GAP: si el Open de la vela ya abre mas alla del nivel |
//|  (saltandolo de golpe), el quiebre es BREAK_GAP y el borde del   |
//|  gap (el Open) define el nuevo extremo estructural.              |
//+------------------------------------------------------------------+
StructResult CStructureEngine::CheckBOS_CHoCH(int shift)
  {
   StructResult res;
   res.Reset();
   if(!m_initialized)
      return res;

   double   h  = Hi(shift);
   double   l  = Lo(shift);
   double   o  = Op(shift);
   datetime t  = Tm(shift);
   double   pc = Cl(shift + 1); // cierre de la barra previa (para detectar gap)

   //--- 1) Rastreo silencioso del retroceso (Punto_Extremo_Temporal) -----
   //    Antes de evaluar quiebres, actualizamos los extremos temporales.
   if(!m_tempLow.valid || l < m_tempLow.price)
      m_tempLow.Set(l, t, IsMarubozuBottom(shift) ? BREAK_NONE : BREAK_WICK);
   if(!m_tempHigh.valid || h > m_tempHigh.price)
      m_tempHigh.Set(h, t, IsMarubozuTop(shift) ? BREAK_NONE : BREAK_WICK);

   //--- 2) Quiebre ALCISTA: la vela cruza el Ultimo_Alto_Confirmado ------
   if(m_lastHigh.valid && h >= m_lastHigh.price)
     {
      // Distinguir mecha vs gap: gap si el Open ya abrio por encima del nivel.
      bool gap = (o > m_lastHigh.price) && (pc < m_lastHigh.price);
      ENUM_BREAK_KIND kind = gap ? BREAK_GAP : BREAK_WICK;

      // El extremo bajo rastreado se BLOQUEA como nuevo Bajo mas Alto (B+A).
      SwingPoint newLow = m_tempLow;
      if(!newLow.valid)
         newLow.Set(m_lastLow.price, m_lastLow.time, BREAK_WICK);

      // En un gap el borde del gap (el Open) actua como referencia A+A inicial.
      double newHighPrice = gap ? MathMax(h, o) : h;

      // Etiquetas: el viejo low rastreado pasa a B+A; el nuevo high a A+A.
      m_BA = newLow;
      m_AA.Set(newHighPrice, t, kind);

      // Evento: CHoCH si veniamos bajistas, BOS si ya alcistas.
      res.event = (m_trend == TREND_BEAR) ? EVENT_CHOCH_BULL : EVENT_BOS_BULL;
      res.kind  = kind;
      res.level = m_lastHigh.price;
      res.time  = t;

      // Confirmar nuevos niveles y resetear el rastreo del proximo retroceso.
      m_lastLow  = newLow;
      m_lastHigh.Set(newHighPrice, t, kind);
      m_trend    = TREND_BULL;

      m_tempLow.Set(newHighPrice, t, BREAK_WICK); // buscara el proximo minimo del retroceso
      m_tempHigh.Reset();
      m_lastProcessed = t;
      return res;
     }

   //--- 3) Quiebre BAJISTA: la vela cruza el Ultimo_Bajo_Confirmado ------
   if(m_lastLow.valid && l <= m_lastLow.price)
     {
      bool gap = (o < m_lastLow.price) && (pc > m_lastLow.price);
      ENUM_BREAK_KIND kind = gap ? BREAK_GAP : BREAK_WICK;

      // El extremo alto rastreado se BLOQUEA como nuevo Alto mas Bajo (A+B).
      SwingPoint newHigh = m_tempHigh;
      if(!newHigh.valid)
         newHigh.Set(m_lastHigh.price, m_lastHigh.time, BREAK_WICK);

      double newLowPrice = gap ? MathMin(l, o) : l;

      m_AB = newHigh;
      m_BB.Set(newLowPrice, t, kind);

      res.event = (m_trend == TREND_BULL) ? EVENT_CHOCH_BEAR : EVENT_BOS_BEAR;
      res.kind  = kind;
      res.level = m_lastLow.price;
      res.time  = t;

      m_lastHigh = newHigh;
      m_lastLow.Set(newLowPrice, t, kind);
      m_trend    = TREND_BEAR;

      m_tempHigh.Set(newLowPrice, t, BREAK_WICK); // buscara el proximo maximo del retroceso
      m_tempLow.Reset();
      m_lastProcessed = t;
      return res;
     }

   //--- 4) Sin quiebre: el precio consolida dentro de la "N". NONE. ------
   m_lastProcessed = t;
   return res;
  }

//+------------------------------------------------------------------+
//| CheckBOS_CHoCH_Live                                              |
//|  Variante intrabar para gatillos rapidos (ej. CHoCH en M1).      |
//|  No reescribe el historico; solo evalua el extremo en vivo.      |
//+------------------------------------------------------------------+
StructResult CStructureEngine::CheckBOS_CHoCH_Live(double live_high, double live_low, double live_open, double prev_close, datetime cur_time)
  {
   StructResult res;
   res.Reset();
   if(!m_initialized)
      return res;

   if(m_lastHigh.valid && live_high >= m_lastHigh.price)
     {
      bool gap = (live_open > m_lastHigh.price) && (prev_close < m_lastHigh.price);
      res.event = (m_trend == TREND_BEAR) ? EVENT_CHOCH_BULL : EVENT_BOS_BULL;
      res.kind  = gap ? BREAK_GAP : BREAK_WICK;
      res.level = m_lastHigh.price;
      res.time  = cur_time;
      return res;
     }

   if(m_lastLow.valid && live_low <= m_lastLow.price)
     {
      bool gap = (live_open < m_lastLow.price) && (prev_close > m_lastLow.price);
      res.event = (m_trend == TREND_BULL) ? EVENT_CHOCH_BEAR : EVENT_BOS_BEAR;
      res.kind  = gap ? BREAK_GAP : BREAK_WICK;
      res.level = m_lastLow.price;
      res.time  = cur_time;
      return res;
     }

   return res;
  }

//+------------------------------------------------------------------+
//| Update                                                           |
//|  Procesa todas las barras cerradas nuevas desde m_lastProcessed. |
//|  Devuelve el ULTIMO evento relevante (o NONE).                   |
//+------------------------------------------------------------------+
StructResult CStructureEngine::Update()
  {
   StructResult last;
   last.Reset();
   if(!m_initialized)
      return last;

   datetime curClosed = Tm(1); // ultima barra cerrada
   if(curClosed <= m_lastProcessed)
      return last; // no hay barra nueva

   // Cuantas barras nuevas cerraron desde la ultima vez.
   int shift = 1;
   int guard = 0;
   // Avanzamos desde la mas antigua no procesada hasta shift=1.
   // Buscamos el indice cuya hora sea m_lastProcessed.
   while(shift < 5000 && Tm(shift) > m_lastProcessed)
      shift++;

   // Procesamos de la mas antigua (shift mayor) a la mas reciente (shift=1).
   for(int s = shift - 1; s >= 1; s--)
     {
      StructResult r = CheckBOS_CHoCH(s);
      if(r.event != EVENT_NONE)
         last = r;
      if(++guard > 5000) break;
     }
   return last;
  }

//+------------------------------------------------------------------+
//| StructuralTarget                                                 |
//|  Objetivo estructural para TP3.                                  |
//+------------------------------------------------------------------+
double CStructureEngine::StructuralTarget() const
  {
   if(m_trend == TREND_BULL)
      return (m_AA.valid ? m_AA.price : m_lastHigh.price);
   if(m_trend == TREND_BEAR)
      return (m_BB.valid ? m_BB.price : m_lastLow.price);
   return 0.0;
  }

//+------------------------------------------------------------------+
//| GetActiveImpulse                                                 |
//|  Origen y destino del impulso vigente para trazar Fibonacci.     |
//+------------------------------------------------------------------+
bool CStructureEngine::GetActiveImpulse(double &origin, double &target) const
  {
   if(m_trend == TREND_BULL && m_lastLow.valid && m_lastHigh.valid)
     {
      origin = m_lastLow.price;   // B+A
      target = m_lastHigh.price;  // A+A
      return true;
     }
   if(m_trend == TREND_BEAR && m_lastHigh.valid && m_lastLow.valid)
     {
      origin = m_lastHigh.price;  // A+B
      target = m_lastLow.price;   // B+B
      return true;
     }
   origin = 0.0; target = 0.0;
   return false;
  }

//+------------------------------------------------------------------+
//| TrendText                                                        |
//+------------------------------------------------------------------+
string CStructureEngine::TrendText() const
  {
   switch(m_trend)
     {
      case TREND_BULL: return "ALCISTA";
      case TREND_BEAR: return "BAJISTA";
      default:         return "SIN SESGO";
     }
  }

#endif // __IMRE_STRUCTURE_ENGINE_MQH__
//+------------------------------------------------------------------+
