//+------------------------------------------------------------------+
//|                                               CTradeManager.mqh   |
//|   Metodologia IMRE - Ejecucion y gestion de riesgo                |
//|                                                                   |
//|   - Entrada principal LIMIT en el 70, SL en el 90.                |
//|   - Reentrada (sweep) en el 90 con SL definitivo en el 105.       |
//|   - TP1 1:3 (seguridad), TP2 runner 1:10, TP3 estructural A+A/B+B. |
//+------------------------------------------------------------------+
#property strict

#ifndef __IMRE_TRADE_MANAGER_MQH__
#define __IMRE_TRADE_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include "IMRE_Defs.mqh"
#include "CFibZones.mqh"

//+------------------------------------------------------------------+
//| Parametros de un setup IMRE listo para ejecutar.                 |
//+------------------------------------------------------------------+
struct ImreSetup
  {
   bool     isBull;        // direccion del trade
   double   entry;         // nivel 70 (entrada principal limit)
   double   slPrimary;     // nivel 90 (SL de la entrada principal)
   double   reentry;       // nivel 90 (reentrada sweep)
   double   slFinal;       // nivel 105 (SL definitivo de la reentrada)
   double   structuralTP;  // A+A / B+B (TP3 estructural)
   double   riskMoney;     // riesgo monetario por idea (opcional)
   datetime created;

   void Reset()
     {
      isBull=false; entry=0; slPrimary=0; reentry=0; slFinal=0;
      structuralTP=0; riskMoney=0; created=0;
     }
  };

//+------------------------------------------------------------------+
//| CTradeManager                                                    |
//+------------------------------------------------------------------+
class CTradeManager
  {
private:
   CTrade            m_trade;
   CPositionInfo     m_pos;
   COrderInfo        m_ord;

   string            m_symbol;
   ulong             m_magic;
   double            m_riskPercent;   // % de balance arriesgado por idea
   double            m_rrTP1;         // 3.0
   double            m_rrTP2;         // 10.0 (runner)
   double            m_splitTP1;      // fraccion de volumen a TP1 (ej 0.5)
   double            m_splitTP2;      // fraccion a TP2
   // el resto (1 - splitTP1 - splitTP2) corre hasta TP3 estructural.

   int               m_digits;
   double            m_point;
   double            m_tickSize;
   double            m_tickValue;
   double            m_volMin;
   double            m_volMax;
   double            m_volStep;

   bool              m_reentryArmed;  // se armo la reentrada tras tocar SL 90
   ImreSetup         m_setup;         // setup vigente

   //--- Registro de etapas alcanzadas por cada ticket (TP1/TP2 parciales).
   ulong             m_tp1Tickets[];  // tickets que ya ejecutaron TP1
   ulong             m_tp2Tickets[];  // tickets que ya ejecutaron TP2

   //--- Normaliza un volumen al step del simbolo.
   double            NormalizeVolume(double vol);
   //--- Calcula volumen por riesgo (% balance) dado entry y SL.
   double            VolumeByRisk(double entry, double sl);
   //--- Helpers de registro de etapas por ticket.
   bool              InList(const ulong &arr[], ulong ticket) const;
   void              AddToList(ulong &arr[], ulong ticket);

public:
                     CTradeManager();
   void              Init(const string symbol, ulong magic, double riskPercent,
                          double rrTP1, double rrTP2, double splitTP1, double splitTP2);

   //--- Coloca el setup completo (entrada limit en 70 + objetivos).
   bool              PlaceSetup(const ImreSetup &s);

   //--- Vigila el sweep: si el precio toca el SL primario (90) sin haber
   //    activado la posicion, arma/coloca la reentrada en 90 con SL en 105.
   void              ManageReentry();

   //--- Gestiona TP escalonado y trailing estructural de las posiciones vivas.
   void              ManageOpenPositions();

   //--- Cancela ordenes pendientes propias.
   void              CancelPending();

   //--- Cuenta posiciones/ordenes propias en el simbolo.
   int               CountPositions();
   int               CountPending();
   bool              HasExposure() { return (CountPositions() + CountPending()) > 0; }

   //--- Accesores.
   ImreSetup         CurrentSetup() const { return m_setup; }
   void              SetStructuralTP(double tp) { m_setup.structuralTP = tp; }
  };

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTradeManager::CTradeManager()
  {
   m_symbol      = _Symbol;
   m_magic       = 20240601;
   m_riskPercent = 1.0;
   m_rrTP1       = 3.0;
   m_rrTP2       = 10.0;
   m_splitTP1    = 0.5;
   m_splitTP2    = 0.3;
   m_reentryArmed= false;
   m_setup.Reset();
  }

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
void CTradeManager::Init(const string symbol, ulong magic, double riskPercent,
                         double rrTP1, double rrTP2, double splitTP1, double splitTP2)
  {
   m_symbol      = symbol;
   m_magic       = magic;
   m_riskPercent = riskPercent;
   m_rrTP1       = rrTP1;
   m_rrTP2       = rrTP2;
   m_splitTP1    = splitTP1;
   m_splitTP2    = splitTP2;

   m_digits   = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   m_point    = SymbolInfoDouble(symbol, SYMBOL_POINT);
   m_tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   m_tickValue= SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   m_volMin   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   m_volMax   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   m_volStep  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   m_trade.SetExpertMagicNumber(m_magic);
   m_trade.SetTypeFillingBySymbol(m_symbol);
   m_trade.SetDeviationInPoints(20);
   m_reentryArmed = false;
  }

//+------------------------------------------------------------------+
//| NormalizeVolume                                                  |
//+------------------------------------------------------------------+
double CTradeManager::NormalizeVolume(double vol)
  {
   if(m_volStep <= 0.0) m_volStep = 0.01;
   double steps = MathFloor(vol / m_volStep);
   double v = steps * m_volStep;
   if(v < m_volMin) v = m_volMin;
   if(v > m_volMax) v = m_volMax;
   return NormalizeDouble(v, 2);
  }

//+------------------------------------------------------------------+
//| VolumeByRisk                                                     |
//|  Volumen tal que la perdida (entry->SL) ~ riskPercent del balance|
//+------------------------------------------------------------------+
double CTradeManager::VolumeByRisk(double entry, double sl)
  {
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (m_riskPercent / 100.0);
   double dist      = MathAbs(entry - sl);
   if(dist <= 0.0 || m_tickSize <= 0.0 || m_tickValue <= 0.0)
      return m_volMin;

   double ticks       = dist / m_tickSize;
   double lossPerLot  = ticks * m_tickValue;
   if(lossPerLot <= 0.0)
      return m_volMin;

   double vol = riskMoney / lossPerLot;
   return NormalizeVolume(vol);
  }

//+------------------------------------------------------------------+
//| PlaceSetup                                                       |
//|  Coloca la entrada principal LIMIT en el 70 con SL en el 90.     |
//|  El TP inicial se fija al objetivo 1:3 (TP1); la gestion de      |
//|  TP2/TP3 se hace dinamicamente en ManageOpenPositions().         |
//+------------------------------------------------------------------+
bool CTradeManager::PlaceSetup(const ImreSetup &s)
  {
   m_setup        = s;
   m_reentryArmed = false;
   ArrayResize(m_tp1Tickets, 0);
   ArrayResize(m_tp2Tickets, 0);

   double vol = VolumeByRisk(s.entry, s.slPrimary);
   double tp1 = CFibZones::TargetByRR(s.entry, s.slPrimary, m_rrTP1, s.isBull);

   double price = NormalizeDouble(s.entry, m_digits);
   double sl    = NormalizeDouble(s.slPrimary, m_digits);
   double tp    = NormalizeDouble(tp1, m_digits);

   bool ok = false;
   if(s.isBull)
      ok = m_trade.BuyLimit(vol, price, m_symbol, sl, tp, ORDER_TIME_GTC, 0, "IMRE Entry 70");
   else
      ok = m_trade.SellLimit(vol, price, m_symbol, sl, tp, ORDER_TIME_GTC, 0, "IMRE Entry 70");

   if(!ok)
      PrintFormat("IMRE: fallo PlaceSetup. ret=%d %s", m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
   return ok;
  }

//+------------------------------------------------------------------+
//| ManageReentry                                                    |
//|  Si el precio barre el SL primario (90) -> arma reentrada en 90  |
//|  con SL definitivo en 105 (sweep/barrido).                       |
//+------------------------------------------------------------------+
void CTradeManager::ManageReentry()
  {
   if(m_setup.entry == 0.0 || m_reentryArmed)
      return;

   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

   bool swept = false;
   if(m_setup.isBull)
      swept = (bid <= m_setup.slPrimary); // el precio toco/barrio el 90
   else
      swept = (ask >= m_setup.slPrimary);

   if(!swept)
      return;

   // Solo reingresar si no quedan posiciones vivas de la idea original.
   if(CountPositions() > 0)
      return;

   CancelPending();

   double vol = VolumeByRisk(m_setup.reentry, m_setup.slFinal);
   double tp1 = CFibZones::TargetByRR(m_setup.reentry, m_setup.slFinal, m_rrTP1, m_setup.isBull);

   double price = NormalizeDouble(m_setup.reentry, m_digits);
   double sl    = NormalizeDouble(m_setup.slFinal, m_digits);
   double tp    = NormalizeDouble(tp1, m_digits);

   bool ok = false;
   if(m_setup.isBull)
      ok = m_trade.BuyLimit(vol, price, m_symbol, sl, tp, ORDER_TIME_GTC, 0, "IMRE Reentry 90");
   else
      ok = m_trade.SellLimit(vol, price, m_symbol, sl, tp, ORDER_TIME_GTC, 0, "IMRE Reentry 90");

   if(ok)
     {
      m_reentryArmed = true;
      PrintFormat("IMRE: reentrada (sweep) colocada en %.5f SL %.5f", price, sl);
     }
  }

//+------------------------------------------------------------------+
//| Helpers de registro de etapas por ticket                         |
//+------------------------------------------------------------------+
bool CTradeManager::InList(const ulong &arr[], ulong ticket) const
  {
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i] == ticket)
         return true;
   return false;
  }

void CTradeManager::AddToList(ulong &arr[], ulong ticket)
  {
   if(InList(arr, ticket)) return;
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n] = ticket;
  }

//+------------------------------------------------------------------+
//| ManageOpenPositions                                              |
//|  TP escalonado:                                                  |
//|   - TP1 1:3 -> cerrar splitTP1 del volumen y mover SL a BE.      |
//|   - TP2 1:10 (runner) sobre el volumen restante.                 |
//|   - TP3 estructural (A+A/B+B) para la ultima porcion.            |
//+------------------------------------------------------------------+
void CTradeManager::ManageOpenPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!m_pos.SelectByTicket(ticket)) continue;
      if(m_pos.Symbol() != m_symbol)    continue;
      if(m_pos.Magic()  != (long)m_magic) continue;

      bool   isBull   = (m_pos.PositionType() == POSITION_TYPE_BUY);
      double entry    = m_pos.PriceOpen();
      double curVol   = m_pos.Volume();
      double price    = isBull ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                               : SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      // Distancia de riesgo original (entry->SL del setup vigente).
      double risk = MathAbs(entry - m_setup.slPrimary);
      if(risk <= 0.0) continue;

      double reached = isBull ? (price - entry) : (entry - price);

      bool tp1Done = InList(m_tp1Tickets, ticket);
      bool tp2Done = InList(m_tp2Tickets, ticket);

      //--- TP1 (1:3): cerrar parcial y asegurar (SL a break-even).
      if(!tp1Done && reached >= m_rrTP1 * risk)
        {
         double closeVol = NormalizeVolume(curVol * m_splitTP1);
         if(closeVol > 0.0 && closeVol < curVol)
            m_trade.PositionClosePartial(ticket, closeVol);
         double be = NormalizeDouble(entry, m_digits);
         m_trade.PositionModify(ticket, be, m_pos.TakeProfit());
         AddToList(m_tp1Tickets, ticket);
         PrintFormat("IMRE: TP1 1:3 alcanzado, parcial cerrado %.2f, SL a BE", closeVol);
         continue;
        }

      //--- TP2 (1:10 runner): cerrar otra porcion.
      if(tp1Done && !tp2Done && reached >= m_rrTP2 * risk)
        {
         double frac = (1.0 - m_splitTP1) > 0.0 ? (m_splitTP2 / (1.0 - m_splitTP1)) : 0.0;
         double closeVol = NormalizeVolume(curVol * frac);
         if(closeVol > 0.0 && closeVol < curVol)
            m_trade.PositionClosePartial(ticket, closeVol);
         AddToList(m_tp2Tickets, ticket);
         PrintFormat("IMRE: TP2 1:10 (runner) alcanzado, parcial cerrado %.2f", closeVol);
         continue;
        }

      //--- TP3 estructural (A+A / B+B): cerrar el resto al tocar el nivel.
      if(m_setup.structuralTP > 0.0)
        {
         bool hit = isBull ? (price >= m_setup.structuralTP)
                           : (price <= m_setup.structuralTP);
         if(hit)
           {
            m_trade.PositionClose(ticket);
            PrintFormat("IMRE: TP3 estructural alcanzado en %.5f, posicion cerrada", m_setup.structuralTP);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| CancelPending                                                    |
//+------------------------------------------------------------------+
void CTradeManager::CancelPending()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!m_ord.Select(ticket)) continue;
      if(m_ord.Symbol() != m_symbol) continue;
      if(m_ord.Magic()  != (long)m_magic) continue;
      m_trade.OrderDelete(ticket);
     }
  }

//+------------------------------------------------------------------+
//| CountPositions / CountPending                                    |
//+------------------------------------------------------------------+
int CTradeManager::CountPositions()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!m_pos.SelectByTicket(ticket)) continue;
      if(m_pos.Symbol() == m_symbol && m_pos.Magic() == (long)m_magic)
         c++;
     }
   return c;
  }

int CTradeManager::CountPending()
  {
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!m_ord.Select(ticket)) continue;
      if(m_ord.Symbol() == m_symbol && m_ord.Magic() == (long)m_magic)
         c++;
     }
   return c;
  }

#endif // __IMRE_TRADE_MANAGER_MQH__
//+------------------------------------------------------------------+
