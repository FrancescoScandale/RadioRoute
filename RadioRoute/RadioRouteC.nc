
/*
*	IMPORTANT:
*	The code will be avaluated based on:
*		Code design  
*
*/
 
 
#include "Timer.h"
#include "RadioRoute.h"

#define MAX_NODES 7
#define PERSON_CODE 10653805


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
	
    //other interfaces, if needed
  }
}
implementation {

  message_t packet; //logic for the msg containing header, footer, metadata, and our payload
  
  // Variables to store the message to send
  message_t queued_packet;
  uint16_t queue_addr;
  uint16_t time_delays[7]={61,173,267,371,479,583,689}; //Time delay in milli seconds
  
  
  bool route_req_sent=FALSE;
  bool route_rep_sent=FALSE;
  
  
  bool locked;
  
  bool actual_send (uint16_t address, message_t* packet);
  bool generate_send (uint16_t address, message_t* packet, uint8_t type);
  
  
  routing_table_entry routing_table[MAX_NODES];
  uint16_t destination = 7;
  bool data_sent = FALSE;
  uint32_t person_code = 0;
  uint32_t j=0;
  
  
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
	if (call AMSend.send(address, packet, sizeof(radio_route_msg_t)) == SUCCESS) {
		dbg("radio_send", "Sending packet");	
		locked = TRUE;
		dbg_clear("radio_send", " at time %s \n", sim_time_string());
		return TRUE;
      }
     return FALSE;
	  
  }
  
  
  event void Boot.booted() {
    dbg("boot","Application booted.\n");
    
    /* Fill it ... */
    call AMControl.start(); //enable the radio
  }

  event void AMControl.startDone(error_t err) {
	/* Fill it ... */
	
	if(err == SUCCESS) {
    	dbg("radio", "Radio on!\n");
		if (TOS_NODE_ID == 1) {
			call Timer1.startOneShot(5000);
        	dbg("timer", "Timer1 started\n");
        }
    }
    else{
		//dbg for error
		dbgerror("radio", "Error in starting the radio\n"); //TODO
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
	
	uint16_t i;
	bool found = FALSE;
	
	// Nodes 1 wants to transmit a packet to node 7,
    // thus check if it already has the destination in its own routing table
  	for (i = 0; i < MAX_NODES; i++) {
        dbg("boot", "Element %hu: dst = %hu\n", i, routing_table[i].dst); //TODO remove this line
        if(routing_table[i].dst == destination){
        	found = TRUE;
        	break;
        } else if(routing_table[i].cost == 0)	break;
    }
    
    if (found) ; //TODO send following routing entry found
    else {
    	if (locked || route_req_sent) { //assumption that a node has to send only one ROUTE_REQ
      		return;
    	}
    	else {
		  	radio_route_msg_t* msg = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
		  	if (msg == NULL) {
				return;
      		}
			msg->type = 1;
			msg->dst = destination;
			if (generate_send(AM_BROADCAST_ADDR, &packet, msg->type) == TRUE) {
				dbg("radio_send", "Send generated\n");
		  	} else {
				dbg("radio_send", "Send is already being generated, cancelling this one.\n");
			}
    	}
    	
    	
    	
    }
  }

  event message_t* Receive.receive(message_t* bufPtr, 
				   void* payload, uint8_t len) {
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
    	dbg("radio_pack",">>>Pack \n \t Payload length %hhu \n", call Packet.payloadLength( bufPtr ));
      
    	switch (received_msg->type) { 	
			case 0: 
				dbg_clear("radio_pack","\t\t Payload \n" );
				dbg_clear("radio_pack", "\t\t msg_type: DATA\t msg_src: %hu\t msg_dst: %hu\t msg_value: %hu \n", received_msg->src, received_msg->dst, received_msg->value);
				found = FALSE;			
				for (i = 0; i < MAX_NODES; i++) {
					if(routing_table[i].dst == destination){
						found = TRUE;
						break;
					} else if(routing_table[i].cost == 0)	break;
				}
				
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
							dbg("radio_send", "Send generated\n");
				  		} else {
							dbg("radio_send", "Send is already being generated, cancelling this one.\n");
						}
				  	}
				}
				else {
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
							dbg("radio_send", "Send generated\n");
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
						// rimanda indietro la risposta //TODO
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
								dbg("radio_send", "Send generated\n");
					  		} else {
								dbg("radio_send", "Send is already being generated, cancelling this one.\n");
							}
					  	}
					}
				}
				break; 
			case 2: 
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
						dbg("radio_pack","TAB: \t dest: %hu\t next_hop: %hu\t cost: %hu\n", routing_table[i].dst, routing_table[i].next_hop, routing_table[i].cost); //TODO remove
						
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
								dbg("radio_send", "Send generated\n");
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
									dbg("radio_send", "Send generated\n");
							  	} else {
									dbg("radio_send", "Send is already being generated, cancelling this one.\n");
								}
							}	
						
						}			  	
					}
				}
				break; 
		}
		
		if (!person_code) {
			for (j = 1; j <= PERSON_CODE; j*=10) ;
			person_code = PERSON_CODE;
		}
	    j = j/10;

		switch((person_code/j) % 3) {
			case 0:
				call Leds.led0Toggle();
				dbg("led_0", "Toggle led 0, updated status %u\n", call Leds.get() & LEDS_LED0);
				break;
			case 1:
				call Leds.led1Toggle();
				dbg("led_1", "Toggle led 1, updated status %u\n", call Leds.get() & LEDS_LED1);
				break;
			case 2:
				call Leds.led2Toggle();
				dbg("led_2", "Toggle led 2, updated status %u\n", call Leds.get() & LEDS_LED2);
				break;
		}

		// 0 means off, >0 means on
		dbg("led_0", "Led 0 status %u\n", call Leds.get() & LEDS_LED0);
		dbg("led_1", "Led 1 status %u\n", call Leds.get() & LEDS_LED1);
		dbg("led_2", "Led 2 status %u\n", call Leds.get() & LEDS_LED2);
		
		person_code %= j;
    	return bufPtr;
	}
}

  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
	/* This event is triggered when a message is sent 
	*  Check if the packet is sent 
	*/
	if (&queued_packet == bufPtr && error == SUCCESS) {
		locked = FALSE;
    	dbg("radio_send", "Sended at time %s\n", sim_time_string());
    	dbg_clear("radio_send", "   >>>>\t\ttype: %hu\tsrc: %hu\tdst: %hu\tvalue: %hu\n", ((radio_route_msg_t*)(call Packet.getPayload(bufPtr, sizeof(radio_route_msg_t))))->type, ((radio_route_msg_t*)(call Packet.getPayload(bufPtr, sizeof(radio_route_msg_t))))->src, ((radio_route_msg_t*)(call Packet.getPayload(bufPtr, sizeof(radio_route_msg_t))))->dst, ((radio_route_msg_t*)(call Packet.getPayload(bufPtr, sizeof(radio_route_msg_t))))->value); //TODO remove
    }
    else{
      dbgerror("radio_send", "Send done error!");
    }
  }
}




