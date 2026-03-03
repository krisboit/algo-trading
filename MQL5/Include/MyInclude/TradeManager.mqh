//+------------------------------------------------------------------+
//| TradeManager.mqh                                                 |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>
#include <Generic\HashMap.mqh>

enum TradeManagementType
  {
   TRADE_MANAGEMENT_TRAIL_SL_1R = 0 // Use Trailing SL with 1R increment and 1R offset
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class PositionInfo
  {
public:
   ulong              ticket;     
   string             symbol;
   long               positionType; 
   double             entryPrice;
   double             initialSL;   
   double             currentSL;   
   double             R;

public:
   // Constructor
    PositionInfo()
     {
     }

   bool FromTicket(ulong _ticket)
      {
         bool success = true;
         if(PositionSelectByTicket(_ticket)) {
            ticket = _ticket;
            currentSL = PositionGetDouble(POSITION_SL);
            entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);  // Entry price
            positionType = PositionGetInteger(POSITION_TYPE);
            symbol = PositionGetString(POSITION_SYMBOL);
            
            long positionId = PositionGetInteger(POSITION_IDENTIFIER);  // Get the pos id
            
            // get initial deal
            int totalDeals = HistoryDealsTotal();
            success = false;
            for(int i=0; i < totalDeals; i++) {
               ulong dealTicket = HistoryDealGetTicket(i);
               long dealPositionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
               long direction = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
               long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
               
               if (dealPositionId == positionId && (dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL) && direction == DEAL_ENTRY_IN) {
                  initialSL = HistoryDealGetDouble(dealTicket, DEAL_SL);                                  
                  R = fixPrice(MathAbs(entryPrice - initialSL));
                  
                  success = true;               
               }
            }                      
         } else {
            success = false;
         }
         return success;
      }
      
   double fixPrice(double n) {
      long digits = SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double factor = MathPow(10, digits);
      return MathFloor(n * factor)/factor;
   }

   // Method to Print Position Info
   void              PrintInfo() const
     {
      Print(
         "Ticket: ", ticket, 
         ", Initial SL: ", initialSL, 
         ", Current SL: ", currentSL,
         ", Entry: ", entryPrice,
         ", R: ", R
      );
     }
  };

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CTradeManager
  {
private:
   TradeManagementType m_tradeManagementType;
   ulong               m_magicNumber;
   CTrade*             m_trade;
   bool                m_shouldUpdateHistory;

   // Map to store position info based on ticket number
   CHashMap<ulong,PositionInfo*>*  m_positionsInfo;

public:
                     CTradeManager(TradeManagementType tradeManagementType = TRADE_MANAGEMENT_TRAIL_SL_1R, bool shouldUpdateHistory = true, ulong magicNumber = NULL);
                    ~CTradeManager();
   void              OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result);
   void              OnTick();

private:
   void              ManageTrades();
   void              TrailSL1R(ulong ticket);
   PositionInfo      GetPositionInfo(ulong ticket);
  };

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTradeManager::CTradeManager(TradeManagementType managementType = TRADE_MANAGEMENT_TRAIL_SL_1R, bool shouldUpdateHistory = true, ulong eaMagicNumber = NULL)
  {
   m_tradeManagementType    = managementType;
   m_magicNumber = eaMagicNumber;
   m_trade       = new CTrade();
   m_shouldUpdateHistory = shouldUpdateHistory;

   m_positionsInfo = new CHashMap<ulong,PositionInfo*>();
   
   datetime currentTime = TimeCurrent();
   HistorySelect(currentTime - 7 * 24 * 3600, currentTime); // load history for last 7 days
  }

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTradeManager::~CTradeManager()
  {
    int totalPositions = PositionsTotal();
    for(int i = 0; i < totalPositions; i++) {
      ulong ticket = PositionGetTicket(i);
      PositionInfo* pi;
      m_positionsInfo.TryGetValue(ticket, pi);
      m_positionsInfo.Remove(ticket);
      delete pi;
    }
    
    delete m_trade;
    delete m_positionsInfo;
  }

//+------------------------------------------------------------------+
//| OnTrade Event Handler                                            |
//+------------------------------------------------------------------+
void CTradeManager::OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
      // update History
      if (m_shouldUpdateHistory) {
         datetime currentTime = TimeCurrent();
         HistorySelect(currentTime - 7 * 24 * 3600, currentTime); // load history for last 7 days
      }
      
      // update positions
      PositionInfo* pi;
      m_positionsInfo.TryGetValue(trans.position, pi);
      m_positionsInfo.Remove(trans.position);
      delete pi;
  }

//+------------------------------------------------------------------+
//| OnTick Event Handler                                             |
//+------------------------------------------------------------------+
void CTradeManager::OnTick()
  {
   ManageTrades();
  }

//+------------------------------------------------------------------+
//| Manage trades                                                    |
//+------------------------------------------------------------------+
void CTradeManager::ManageTrades()
  {
   // go through open positions with correct magicNumber
   // execute trade management specific function for each position
   int totalPositions = PositionsTotal();
   
   for(int i = 0; i < totalPositions; i++) {
      ulong ticket = PositionGetTicket(i);
      
      if (ticket == 0) {
       Print("Error retriving position ticket: ",i," ",GetLastError());  
      }
      
      if (m_magicNumber == PositionGetInteger(POSITION_MAGIC) || m_magicNumber == NULL) {
         switch(m_tradeManagementType)
           {
            case TRADE_MANAGEMENT_TRAIL_SL_1R:
               TrailSL1R(ticket);
               break;
           }
      }
   }
  }

//+------------------------------------------------------------------+
//| Strategy 1 Implementation                                        |
//+------------------------------------------------------------------+
void CTradeManager::TrailSL1R(ulong ticket)
  {
   // SL trail from entry price + 1RR, and the trailing step is 1RR
   // get position info
   PositionInfo* positionInfo;
   if (m_positionsInfo.ContainsKey(ticket)) {
      // Print("Got key from cache");
      //positionInfo.PrintInfo();
      m_positionsInfo.TryGetValue(ticket, positionInfo);
   } else {
      // Print("fetch key...");
      //positionInfo.PrintInfo();
      positionInfo = new PositionInfo();
      positionInfo.FromTicket(ticket);
      m_positionsInfo.Add(ticket, positionInfo);
  }
   
   
   // check if current price > entry + 1R
   // move stopLoss
   double bidPrice = SymbolInfoDouble(positionInfo.symbol, SYMBOL_BID);  // Bid price for selling
   double askPrice = SymbolInfoDouble(positionInfo.symbol, SYMBOL_ASK);  // Ask price for buying
   
   if (positionInfo.positionType == POSITION_TYPE_BUY) {
      if (bidPrice >= positionInfo.entryPrice) {
         double rs = MathFloor((bidPrice - positionInfo.entryPrice)/positionInfo.R);
         double nextSL = positionInfo.fixPrice(positionInfo.entryPrice + (rs-1)*positionInfo.R);
         if (nextSL > positionInfo.currentSL) {
            // update sl on position
            // Print("Next SL: ", nextSL, "  RS: ", rs, " BID: ", bidPrice);
            m_trade.PositionModify(ticket, nextSL, NULL);
         }                  
      }
   } else if (positionInfo.positionType == POSITION_TYPE_SELL) {
      if (askPrice <= positionInfo.entryPrice) {
         double rs = MathFloor((positionInfo.entryPrice - askPrice)/positionInfo.R);
         double nextSL = positionInfo.entryPrice - (rs-1)*positionInfo.R;
         if (nextSL < positionInfo.currentSL) {
            // update sl on position
            m_trade.PositionModify(ticket, nextSL, NULL);
         }       
      }
   }
  }

//+------------------------------------------------------------------+
