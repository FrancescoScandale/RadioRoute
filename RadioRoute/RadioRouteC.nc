#include "Timer.h"
#include "RadioRoute.h"

#define MAX_NODES 7
#define PERSON_CODE 10616610


module RadioRouteC @safe() {
  uses {
  
    /****** INTERFACES *****/
	interface Boot;

    //interfaces for communication
    interface Receive;
    interface AMSend;
    interface SplitControl as AMControl;
    interface Packet;
    
	//interface for timers
	interface Timer<TMilli> as Timer0;
	interface Timer<TMilli> as Timer1;
	
	//interface for LED
	interface Leds;
  }
}
implementation {

  message_t packet; //logic for the msg containing header, footer, metadata, and our payload
  
  // Variables to store the message to send
  message_t queued_packet;
  uint16_t queue_addr;
  uint16_t time_delays[7]={61,173,267,371,479,583,689}; //Time delay in milli seconds
  
  //bools to check if the node has already sent or received a message
  //(assumption of the challenge: only 1 req and 1 reply)
  bool route_req_sent=FALSE;
  bool route_rep_sent=FALSE;
  
  //bool used to check if the message of type 0 (data) has already been sent
  bool data_sent = FALSE;
  
  bool locked;
  
  bool actual_send (uint16_t address, message_t* packet);
  bool generate_send (uint16_t address, message_t* packet, uint8_t type);
  
  
  routing_table_entry routing_table[MAX_NODES]; //local routing table
  uint16_t destination = 7; //final destination of the program
  uint32_t person_code = 0; //modified person code based on the leds
  uint32_t j=0;	//iteration variables to handle changes in the leds
  
  
  bool generate_send (uint16_t address, message_t* packet, uint8_t type){
  /*
  * 
  * Function to be used when performing the send after the receive message event.
  * It store the packet and address into a global variable and start the timer execution to schedule the send.
  * It allow the sending of only one message for each REQ and REP type
  * @Input:
  *		address: packet destination address
  *		packet: full packet to be sent (Not only Payload)
  *		type: payload message type
  *
  * MANDATORY: DO NOT MODIFY THIS FUNCTION
  */
  	if (call Timer0.isRunning()){
  		return FALSE;
  	}else{
  	if (type == 1 && !route_req_sent ){
  		route_req_sent = TRUE;
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;
  	}else if (type == 2 && !route_rep_sent){
  	  	route_rep_sent = TRUE;
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;
  	}else if (type == 0){
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;	
  	}
  	}
  	return TRUE;
  }
  
  event void Timer0.fired() {
  	/*
  	* Timer triggered to perform the send.
  	* MANDATORY: DO NOT MODIFY THIS FUNCTION
  	*/
  	actual_send (queue_addr, &queued_packet);
  }
  
  bool actual_send (uint16_t address, message_t* packet){
	/*
	* Implement here the logic to perform the actual send of the packet using the tinyOS interfaces
	*/

	//start sending the packets
	if (call AMSend.send(address, packet, sizeof(radio_route_msg_t)) == SUCCESS) {
		dbg("radio_send", "Sending packet");	
		locked = TRUE; //lock the radio
		dbg_clear("radio_send", " at time %s \n", sim_time_string());
		return TRUE;
      }
     return FALSE;
	  
  }
  
  
  event void Boot.booted() {
    dbg("boot","Application booted.\n");
    
    call AMControl.start(); //enable the radio
  }

  event void AMControl.startDone(error_t err) {
	
	if(err == SUCCESS) {
    	dbg("radio", "Radio on!\n");
		if (TOS_NODE_ID == 1) {	//only node 1 starts timer1, in order to start the algorithm
			call Timer1.startOneShot(5000);
        	dbg("timer", "Timer1 started at time %s\n", sim_time_string());
        }
    }
    else{
		//dbg for error
		dbgerror("radio", "Error in starting the radio\n");
		call AMControl.start();
    }
  }

  event void AMControl.stopDone(error_t err) {
    /* Fill it ... */
  }
  
  event void Timer1.fired() {
	/*
	* Implement here the logic to trigger the Node 1 to send the first REQ packet
	*/

	if (locked || route_req_sent) { //assumption that a node has to send only one ROUTE_REQ
		return;
	}
	else {
		//build packet and retrive the payload
		radio_route_msg_t* msg = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
		if (msg == NULL) {
			return;
		}

		//set variables
		msg->type = 1;
		msg->dst = destination;

		//start the sending algorithm
		if (generate_send(AM_BROADCAST_ADDR, &packet, msg->type) == TRUE) {
		} else {
			dbg("radio_send", "Send is already being generated, cancelling this one.\n");
		}
	}	
  }

  event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
	/*
	* Parse the receive packet.
	* Implement all the functionalities
	* Perform the packet send using the generate_send function if needed
	* Implement the LED logic and print LED status on Debug
	*/
	
	uint16_t i; //index for cycles
	bool found; //flag to search in the routing table
	
	radio_route_msg_t* msg;
	
	if (len != sizeof(radio_route_msg_t)) {return bufPtr;}
    else {
    	radio_route_msg_t* received_msg = (radio_route_msg_t*)payload;
      
    	dbg("radio_rec", "Received packet at time %s\n", sim_time_string());
    	dbg("radio_pack","\t Payload length %hhu \n", call Packet.payloadLength( bufPtr ));
      
    	switch (received_msg->type) { 	
			case 0: //data message
				dbg_clear("radio_pack","\t\t Payload \n" );
				dbg_clear("radio_pack", "\t\t msg_type: DATA\t msg_src: %hu\t msg_dst: %hu\t msg_value: %hu \n", received_msg->src, received_msg->dst, received_msg->value);
				found = FALSE;			
				for (i = 0; i < MAX_NODES; i++) {
					if(routing_table[i].dst == destination){
						found = TRUE;
						break;
					} else if(routing_table[i].cost == 0)	break;
				}
				
				//case 0.1: destination node found in the routing table
				if(found) { 
					if (locked) {
		  				return bufPtr;
					}
					else {
						msg = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
				  		if (msg == NULL) {
							return bufPtr;
			  			}
						msg->type = 0;
						msg->src = TOS_NODE_ID;
						msg->dst = received_msg->dst;
						msg->value = received_msg->value;
						if (generate_send(routing_table[i].next_hop, &packet, msg->type) == TRUE) {
				  		} else {
							dbg("radio_send", "Send is already being generated, cancelling this one.\n");
						}
				  	}
				} else if(TOS_NODE_ID == received_msg->dst){ //case 0.2: data arrived at destination node
					dbg("radio", "Data arrived ad destination! Data: %hu\n",received_msg->value);
				}
				else { //case 0.3: destination node not in the routing table, can't proceed
					dbg("radio", "Can't send to the next node: I don't have the destination in my routing table!\n");
				}
				
				break;

			case 1: //Route request message
				dbg_clear("radio_pack","\t\t Payload \n" );
				dbg_clear("radio_pack", "\t\t msg_type: ROUTE_REQ\t msg_dst: %hu\t\n", received_msg->dst);
			
				// case 1.1: The node is the one required
				if (TOS_NODE_ID == received_msg->dst){
					if (locked || route_rep_sent) {
		  				return bufPtr;
					}
					else {
						msg = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
				  		if (msg == NULL) {
							return bufPtr;
			  			}
						msg->type = 2;
						msg->src = TOS_NODE_ID;
						msg->dst = received_msg->dst;
						msg->value = 1;
						if (generate_send(AM_BROADCAST_ADDR, &packet, msg->type) == TRUE) {
				  		} else {
							dbg("radio_send", "Send is already being generated, cancelling this one.\n");
						}
				  	}
				} else { //case 1.2: The node is not the one required	
					//search in the routing table					
					found = FALSE;
		  			for (i = 0; i < MAX_NODES; i++) {
						if(routing_table[i].dst == destination){
							found = TRUE;
							break;
						} else if(routing_table[i].cost == 0)	break;
					}
				
					// case 1.2.1: The node is in the routing table
					if(found) {
						if (locked || route_req_sent) {
		  					return bufPtr;
						}
						else {
							msg = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
					  		if (msg == NULL) {
								return bufPtr;
				  			}
							msg->type = 2;
							msg->src = TOS_NODE_ID;
							msg->dst = received_msg->dst;
							msg->value = routing_table[i].cost+1;
							if (generate_send(AM_BROADCAST_ADDR, &packet, msg->type) == TRUE) {
					  		} else {
								dbg("radio_send", "Send is already being generated, cancelling this one.\n");
							}
					  	}
					} 
					// case 1.2.2: The node is not in the routing table
					else {
						if (locked || route_req_sent) {
		  					return bufPtr;
						}
						else {
							msg = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
					  		if (msg == NULL) {
								return bufPtr;
				  			}
							msg->type = 1;
							msg->dst = received_msg->dst;
							if (generate_send(AM_BROADCAST_ADDR, &packet, msg->type) == TRUE) {
					  		} else {
								dbg("radio_send", "Send is already being generated, cancelling this one.\n");
							}
					  	}
					}
				}
				break; 

			case 2: //route reply message
				dbg_clear("radio_pack","\t\t Payload \n" );
				dbg_clear("radio_pack", "\t\t msg_type: ROUTE_REPLY\t msg_src: %hu\t msg_dst: %hu\t msg_value: %hu \n", received_msg->src, received_msg->dst, received_msg->value);
				//ROUTE_REPLY arrives at everyone but node 7 doesn't have to answer
				if (TOS_NODE_ID != received_msg->dst){
					found = FALSE;
		  			for (i = 0; i < MAX_NODES; i++) {
						if(routing_table[i].dst == destination){
							found = TRUE;
							break;
						} else if(routing_table[i].cost == 0)	break; //check done to find the 1st empty position in the routing table
					}

					//if not in the routing table or received cost is smaller
					if(!found || (found && routing_table[i].cost>received_msg->value)) {
						routing_table[i].dst = received_msg->dst;
						routing_table[i].next_hop = received_msg->src;
						routing_table[i].cost = received_msg->value;
						
						//node 1 starts sending the data - last ROUTE_REPLY received
						if (TOS_NODE_ID == 1 && routing_table[i].dst == destination && !data_sent){
							msg = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
						  	if (msg == NULL) {
								return bufPtr;
					  		}
							msg->type = 0;
							msg->src = TOS_NODE_ID;
							msg->dst = destination;
							msg->value = 5;
							if (generate_send(routing_table[i].next_hop, &packet, msg->type) == TRUE) {
								data_sent = TRUE;
						  	} else {
								dbg("radio_send", "Send is already being generated, cancelling this one.\n");
							}					
						}
						else {
						
							if (locked || route_rep_sent) {
			  					return bufPtr;
							}
							else {
								// forward reply
								msg = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
							  	if (msg == NULL) {
									return bufPtr;
						  		}
								msg->type = 2;
								msg->src = TOS_NODE_ID;
								msg->dst = received_msg->dst;
								msg->value = received_msg->value + 1; 
								if (generate_send(AM_BROADCAST_ADDR, &packet, msg->type) == TRUE) {
							  	} else {
									dbg("radio_send", "Send is already being generated, cancelling this one.\n");
								}
							}	
						
						}			  	
					}
				}
				break; 
		}
		
		//person_code re-generation
		if (!person_code) {
			for (j = 1; j <= PERSON_CODE; j*=10) ;
			person_code = PERSON_CODE;
		}
	    j = j/10;

		//choose the leftmost digit and toggle the corresponding led
		switch((person_code/j) % 3) {
			case 0:
				call Leds.led0Toggle();
				dbg("led_0", "Toggle led 0");
				break;
			case 1:
				call Leds.led1Toggle();
				dbg("led_1", "Toggle led 1");
				break;
			case 2:
				call Leds.led2Toggle();
				dbg("led_2", "Toggle led 2");
				break;
		}
		dbg("radio", "Led status: %u%u%u\n", call Leds.get() & LEDS_LED0, call Leds.get() & LEDS_LED1, call Leds.get() & LEDS_LED2);
		
		//update person_code
		person_code %= j;
    	return bufPtr;
	}
}

  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
	/* This event is triggered when a message is sent 
	*  Check if the packet is sent 
	*/
	if (&queued_packet == bufPtr && error == SUCCESS) {
		locked = FALSE; //unlock the radio
    }
    else{
		locked = FALSE; //free the radio for other messages
      	dbgerror("radio_send", "Send done error!");
    }
  }
}




