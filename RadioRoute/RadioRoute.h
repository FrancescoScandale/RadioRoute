

#ifndef RADIO_ROUTE_H
#define RADIO_ROUTE_H

typedef nx_struct radio_route_msg {

	//field 1
	nx_uint8_t type;
	
	//field 2
	nx_uint16_t src;
	
	//field 3
	nx_uint16_t dst; //when ROUTE_RQS or ROUTE_REPLY -> "node requested"
	
	//field 4
	nx_uint16_t value; //when ROUTE_REPLY -> "cost"
} radio_route_msg_t;

typedef nx_struct routing_table_entry {

	//field 1
	nx_uint16_t dst;
	
	//field 2
	nx_uint16_t next_hop;
	
	//field 3
	nx_uint16_t cost;
} routing_table_entry;

enum {
  AM_RADIO_COUNT_MSG = 6,
};

#endif
