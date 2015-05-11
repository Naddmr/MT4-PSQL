/*
    Copyright 2015 Naddmr, http://www.forexfactory.com

    This file is part of the mt4psql project.

    mt4psql is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    mt4psql is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with mt4psql.  If not, see <http://www.gnu.org/licenses/>.
*/


-- base data of all trade types of MT4
drop table if exists t_trade_types cascade;
create table mt_trade_types (
	trade_type	int,
	trade_dsc	varchar(16),
	trade_long_dsc	varchar(64),
	constraint pk_trade_types primary key (trade_type)
);
insert into t_trade_types (trade_dsc, trade_type, trade_long_dsc) values 
	('OP_BUY', 	0, 'Buy operation'),
	('OP_SELL', 	1, 'Sell operation'),
	('OP_BUYLIMIT', 2, 'Buy limit pending order'),
	('OP_SELLLIMIT',3, 'Sell limit pending order'),
	('OP_BUYSTOP',	4, 'Buy stop pending order'),
	('OP_SELLSTOP', 5, 'Sell stop pending order');


-- base data of all trades entered into the system
drop table mt_trades cascade;
create table mt_trades (
	ticket_id	bigint,
	constraint pk_trades primary key (ticket_id),
	trade_type	int,
	constraint fk_trade_trade_type foreign key (trade_type) references mt_trade_types (trade_type) 
	on update cascade on delete cascade,
	open_time	timestamp not null default now(),
	expiration_time	timestamp default null,
	lot_size	numeric(5,4) not null,
	close_time	timestamp,
	open_price	numeric(19,5) default 0,
	close_price	numeric(19,5) default 0,
	sl_price	numeric(19,5) default 0,
	tp_price	numeric(19,5) default 0
);

drop table mt_trade_scaleouts;
create table mt_trade_scaleouts (
	orig_ticket_id		bigint default 0,
	scaleout_ticket_id	bigint default 0,
	constraint pk_trade_scaleouts primary key (orig_ticket_id, scaleout_ticket_id),
	constraint fk_scaleout_orig_trades foreign key (orig_ticket_id) references mt_trades (ticket_id)
	on update cascade on delete cascade
);

drop table mt_trade_scaleins;
create table mt_trade_scaleins (
	orig_ticket_id		bigint default 0,
	scalein_ticket_id	bigint default 0,
	constraint pk_trade_scaleins primary key (orig_ticket_id, scalein_ticket_id),
	constraint fk_scalein_orig_trades foreign key (orig_ticket_id) references mt_trades (ticket_id)
	on update cascade on delete cascade
);


