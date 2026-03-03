//+------------------------------------------------------------------+
//|                                                      Manager.mqh |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#include <Generic\HashMap.mqh>

class PositionInfo {
public:
    ulong              positionTicket;
    ulong              orderTicket;
    double             initialSL;
    double             R;

public:
    // Constructor
                     PositionInfo() {
    }
};

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class SignalExecutor {
private:
   CHashMap<long,PositionInfo*>* positionsInfo;
public:
    void             SignalExecutor(CHashMap<long,PositionInfo*> &posInfo){
      positionsInfo = posInfo;
    };
};


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class PositionExitManager {
private:
   CHashMap<long,PositionInfo*>* positionsInfo;
public:
    void             PositionExitManager(CHashMap<long,PositionInfo*> &posInfo){
      positionsInfo = posInfo;
    };
};


//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class Manager {
private:
    SignalExecutor*      signalExecutor;
    PositionExitManager* positionExitManager;
    CHashMap<long,PositionInfo*>* positionsInfo;
public:
    void             Manager() {
      positionsInfo = new CHashMap<long,PositionInfo*>();
      signalExecutor = new SignalExecutor(positionsInfo);
      positionExitManager = new PositionExitManager(positionsInfo);
    };
    void             ~Manager() {
      delete signalExecutor;
      delete positionExitManager;
      
      // TODO: delete maps keys
      delete positionsInfo;
    }
    void             OnTick();
    void             OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result);
    void             executeSignal();

};

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
