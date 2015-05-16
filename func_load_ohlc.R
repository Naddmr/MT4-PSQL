#    Copyright 2015 Naddmr, http://www.forexfactory.com
#
#    This file is part of the mt4psql project.
#
#    mt4psql is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    mt4psql is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with mt4psql.  If not, see <http://www.gnu.org/licenses/>.
#
#
# This is an example to read OHLC data from PostgreSQL
# into [R] and to draw some chart on the data
#
# Change the variables to your needs
# they are parameters to the function defined below.
#########################
OANDA_BROKER_ID = 2
FXCM_BROKER_ID = 1
PAIR_NAME <- "USDJPY"
FROM_TIME  <- "2015-05-08 14:25:00"
UNTIL_TIME <- "2015-05-08 15:00:00"
TIMEFRAME_NAME <- 'S30';
thisTZ <- "Europe/Berlin"
#########################
pkgs <- c('zoo', 'xts', 'lattice', 'fBasics', 'MASS', 'quantmod', 'TTR', 'RPostgreSQL')
lapply(pkgs, require, character.only=T)
remove(pkgs)
#
getOption("digits.secs")
opts <- options(digits.secs = 3)

fetch_ohlc <- function(
	broker_id, 
	alias_name,
	timeframe_name,
	from_timestamp,
	until_timestamp
) {
	# Connect to the PostgreSQL database 
	con <- dbConnect(PostgreSQL(), user="postgres", host="192.168.102.254", password="",dbname="mtforex")
	# Create a query for the data of the PostgreSQL server
	# Note that the time zone has to be supplied as well!
	q <- paste(
		"select
			o.*
		 from 
			t_mt4_ohlc o
			join t_mt4_pair_timeframes f using (timeframe_id)
			join t_mt4_pairdata p using (pair_id)
			join t_mt4_brokers b using (broker_id)
			join t_mt4_pairaliases pa using (pair_id)
			join t_mt4_aliasnames a using (alias_id)
		where
			b.broker_id=", broker_id, " and ",
			" a.pairname='", alias_name, "' and ",
			" f.timeframe_name='", timeframe_name, "' and ",
			" o.ttimestamp>='", from_timestamp, " ", thisTZ, "'::timestamp with time zone and ",
			" o.ttimestamp<='", until_timestamp, " ", thisTZ, "'::timestamp with time zone;",
		sep=""
	)
	rs <- dbSendQuery(con, q)
	rc <- fetch(rs, n=-1)
	dbClearResult(rs)
	dbDisconnect(con)
	if (nrow(rc)>0) {
		# Note that no time zone recalculation is needed here!
		rc <- as.xts(rc[,c("dopenbid", "dhighbid", "dlowbid", "dclosebid", "dtickvolume")], order.by=rc$ttimestamp)
		names(rc) <- c("open", "high", "low", "close", "volume")
	}
	
	return(rc)
}

oanda  <- fetch_ohlc(OANDA_BROKER_ID, PAIR_NAME, TIMEFRAME_NAME, FROM_TIME, UNTIL_TIME)
fxcm   <- fetch_ohlc(FXCM_BROKER_ID, PAIR_NAME, TIMEFRAME_NAME, FROM_TIME, UNTIL_TIME)
#
prices <- oanda
chart_Series(prices, 
			 name=paste("OANDA ", PAIR_NAME, " in TF ", TIMEFRAME_NAME, sep=""),
			 log.scale=FALSE,
			 show.grid=TRUE
)

prices <- fxcm
chart_Series(prices, 
			 name=paste("FXCM ", PAIR_NAME, " in TF ", TIMEFRAME_NAME, sep=""),
			 log.scale=FALSE,
			 show.grid=TRUE
)

# but then - this works too... 

source("func_load_ticks.R")

oanda_ohlc <- to.period(oanda, k=30, "seconds", OHLC=TRUE)
fxcm_ohlc <-  to.period(fxcm, k=30, "seconds", OHLC=TRUE)
prices <- oanda_ohlc
chart_Series(prices, 
			 name=paste("OANDA ", PAIR_NAME, " in TF ", "S30", sep=""),
			 log.scale=FALSE,
			 show.grid=TRUE
)

