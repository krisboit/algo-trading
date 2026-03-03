//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2020, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+
#include "websocket.mqh"

typedef void (*MessageCallback)(string message);

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CTVWebSocketClient
  {
private:
   CWebsocket        ws;
   MessageCallback   onMessageCallback;
   bool              isConnected;
   string            lastError;

public:
                     CTVWebSocketClient()
     {
      isConnected = false;
      onMessageCallback = NULL;
      lastError = "";
     }

                    ~CTVWebSocketClient()
     {
      Disconnect();
     }

   bool              Connect(string serverAddress, int port = 443, string appName = NULL, bool secure = true)
     {
      if(isConnected)
         return true;

      bool result = ws.Connect(serverAddress, port, appName, secure);
      if(!result)
        {
         lastError = ws.LastErrorMessage();
         return false;
        }

      isConnected = true;
      return true;
     }

   void              Disconnect()
     {
      if(isConnected)
        {
         ws.Close();
         isConnected = false;
        }
     }

   bool              SendMessage(string message)
     {
      if(!isConnected)
         return false;

      bool result = ws.SendString(message);
      if(!result)
        {
         lastError = ws.LastErrorMessage();
         return false;
        }
      return true;
     }

   void              SetOnMessageCallback(MessageCallback callback)
     {
      onMessageCallback = callback;
     }

   bool              CheckForMessages()
     {
      if(!isConnected)
         return false;

      string response;
      ulong bytesRead = ws.ReadString(response);

      if(bytesRead > 0)
        {

         // Process the message
         if(onMessageCallback != NULL)
           {
            onMessageCallback(response);
           }
         return true;
        }
      else
        {
         // No message received or error
         uint lastError = ws.LastError();
         if(lastError != 0)
           {
            this.lastError = ws.LastErrorMessage();
           }
         return false;
        }
      return true;
     }

   string            GetLastError()
     {
      return lastError;
     }
  };
//+------------------------------------------------------------------+
