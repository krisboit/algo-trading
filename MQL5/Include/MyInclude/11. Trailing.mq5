//+------------------------------------------------------------------+
//|                                                   Expert complex |
//|                                                  Ciprian Vorovei |
//|                                    https://www.therichorpoor.com |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TRAILING()
  {
   int Pozitii = PositionsTotal();//extrage nr de pozitii executate

   if(Pozitii > 0)//avem cel putin o pozitie
     {
      for(int i=0;i<nrPozitiiMax;i++)
        {
         if(Ticket[i] == 0)
            continue;

         for(int a = 0; a<Pozitii;a++)
           {
            ulong ID_Pozitie = PositionGetTicket(a);//extrage ID pozitiei curente

            if(ID_Pozitie == 0)
               continue;

            if(ID_Pozitie == Ticket[i])
              {
               if(PositionSelectByTicket(ID_Pozitie) ==true)//Pozitia a fost selectata cu succes si poate fi citita
                 {
                  double Nivel_Bid = SymbolInfoDouble(NULL,SYMBOL_BID);
                  double Nivel_Ask = SymbolInfoDouble(NULL,SYMBOL_ASK);

                  bool Trail = false;//va returan true daca modificarea a fost executata

                  if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)//Ordinul de executat si este de tip BUY
                    {
                     if(Nivel_Bid >= TP_Trail[i])
                       {
                        //--facem trail
                        if(SL[i] >= PositionGetDouble(POSITION_PRICE_OPEN))//pretul a fost mutat dela la BE
                          {
                           SL[i] = TP_Trail[i] - R[i];//Calculez nivelul inferior unde plasez SL
                           TP_Trail[i] = TP_Trail[i] + R[i];//Calculez urmatorul nivel la care mut SL

                           Trail = Ordin.PositionModify(Ticket[i],SL[i],PositionGetDouble(POSITION_TP));

                           if(Trail == true)//modificarea a fost facuta cu succes
                             {
                              Print("Pozitia ", Ticket[i], " am mutat atins urmatorul TO, facem trailiing.");
                             }

                           if(Trail == false)
                             {
                              Print("Nu am putut modifica ordinul ", Ticket[i]," Cod eroare: ",GetLastError());
                             }
                          }
                        //---Muta SL la BE
                        if(SL[i] < PositionGetDouble(POSITION_PRICE_OPEN))//pretul nu a fost mutat la Entry
                          {
                           SL[i]= PositionGetDouble(POSITION_PRICE_OPEN);//extrage pretul de executie
                           TP_Trail[i] = TP_Trail[i] + R[i];//La valoarea actuala TP1 adaug R si obtin TP2

                           Trail = Ordin.PositionModify(Ticket[i],SL[i],PositionGetDouble(POSITION_TP));

                           if(Trail == true)//modificarea a fost facuta cu succes
                             {
                              Print("Pozitia ", Ticket[i], " am mutat SL la Entry. Suntem in Breakeven");
                             }

                           if(Trail == false)
                             {
                              Print("Nu am putut modifica ordinul ", Ticket[i]," Cod eroare: ",GetLastError());
                             }
                          }

                      }
                    }

                  if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)//Ordinul de executat si este de tip SELL
                    {
                     if(Nivel_Ask <= TP_Trail[i])
                       {
                        //--facem trail
                        if(SL[i] <= PositionGetDouble(POSITION_PRICE_OPEN))//pretul a fost mutat dela la BE
                          {
                           SL[i] = TP_Trail[i] + R[i];//Calculez nivelul inferior unde plasez SL
                           TP_Trail[i] = TP_Trail[i] - R[i];//Calculez urmatorul nivel la care mut SL

                           Trail = Ordin.PositionModify(Ticket[i],SL[i],PositionGetDouble(POSITION_TP));

                           if(Trail == true)//modificarea a fost facuta cu succes
                             {
                              Print("Pozitia ", Ticket[i], " am mutat atins urmatorul TO, facem trailiing.");
                             }

                           if(Trail == false)
                             {
                              Print("Nu am putut modifica ordinul ", Ticket[i]," Cod eroare: ",GetLastError());
                             }
                          }
                        //---Muta SL la BE
                        if(SL[i] > PositionGetDouble(POSITION_PRICE_OPEN))//pretul nu a fost mutat la Entry
                          {
                           SL[i] = PositionGetDouble(POSITION_PRICE_OPEN);//extrage pretul de executie
                           TP_Trail[i] = TP_Trail[i] - R[i];//La valoarea actuala TP1 adaug R si obtin TP2

                           Trail = Ordin.PositionModify(Ticket[i],SL[i],PositionGetDouble(POSITION_TP));

                           if(Trail == true)//modificarea a fost facuta cu succes
                             {
                              Print("Pozitia ", Ticket[i], " am mutat SL la Entry. Suntem in Breakeven");
                             }

                           if(Trail == false)
                             {
                              Print("Nu am putut modifica ordinul ", Ticket[i]," Cod eroare: ",GetLastError());
                             }
                          }

                       }
                    }
                 }

              }

           }

        }



     }

  }
//+------------------------------------------------------------------+
