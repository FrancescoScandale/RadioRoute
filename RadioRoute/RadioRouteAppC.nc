
 
#include "RadioRoute.h"


configuration RadioRouteAppC {}
implementation {
/****** COMPONENTS *****/
  components MainC, RadioRouteC as App;
  //add the other components here
  components LedsC; //leds components
  
  components new AMSenderC(AM_RADIO_COUNT_MSG); //for sending msgs (AM_RADIO_COUNT_MSG constant defined in the RadioRoute.h file (todo forse da cambiare in 6)
  components new AMReceiverC(AM_RADIO_COUNT_MSG); //for receiving msgs
  components ActiveMessageC; //for managing msgs  
  
  components new TimerMilliC() as Timer0;
  components new TimerMilliC() as Timer1;  
  
  /****** INTERFACES *****/
  //Boot interface
  App.Boot -> MainC.Boot;
  
  /****** Wire the other interfaces down here *****/
  App.Receive -> AMReceiverC;
  App.AMSend -> AMSenderC;
  App.AMControl -> ActiveMessageC;
  App.Leds -> LedsC;
  App.Timer0 -> Timer0;
  App.Timer1 -> Timer1;
  App.Packet -> AMSenderC;

}


