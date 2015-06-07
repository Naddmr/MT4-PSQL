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
# This is an example to read tick data from PostgreSQL
# into [R] and to draw some chart on the data
#
# Change the variables to your needs
# they are parameters to the function defined below.
#####################
OANDA_BROKER_ID = 2
FXCM_BROKER_ID = 3
PAIR_NAME <- "XAUUSD"
FROM_TIME  <- "2015-06-03 11:27:00"
UNTIL_TIME <- "2015-06-03 11:29:00"
thisTZ <- "Europe/Berlin"
#####################
#
pkgs <- c('zoo', 'xts', 'lattice', 'fBasics', 'MASS', 'quantmod', 'TTR', 'RPostgreSQL')
lapply(pkgs, require, character.only=T)
remove(pkgs)
getOption("digits.secs")
opts <- options(digits.secs = 4)

fetch_ticks <- function(
		broker_id, 
		alias_name,
		from_timestamp,
		until_timestamp
) {
	# Connect to the PostgreSQL database 
	con <- dbConnect(PostgreSQL(), user="postgres", host="192.168.102.254", password="",dbname="mtforex")
	
	# Create a query for the data of the PostgreSQL server
	q <- paste(
		"select
			a.pairname,
			t.*
		 from 
			t_mt4_brokers b
			join t_mt4_pairdata p using (broker_id)
			join t_mt4_pairaliases pa using (pair_id)
			join t_mt4_aliasnames a using (alias_id)
			join t_mt4_ticks t using (pair_id)
		 where
			b.broker_id=", broker_id, " and ",
			" a.pairname='", alias_name, "' and ",
			" t.loctimestamp>='", from_timestamp,  " ", thisTZ, "'::timestamp with time zone and ",
			" t.loctimestamp<='", until_timestamp, " ", thisTZ, "'::timestamp with time zone",
		sep=""
	)
	rs <- dbSendQuery(con, q)
	rc <- fetch(rs, n=-1)
	dbClearResult(rs)
	dbDisconnect(con)
	# As the server runs in the UTC timezone and 
	# the local timestamp gotten from Lazarus is without timezone
	# the wrong time zone recalculation is applied
	# Force no time zone
	if (nrow(rc)>0) {
		# Note that no time zone recalculation is needed here any longer!
		rc <- as.xts(rc[,c("dbid", "dask")], order.by=rc$loctimestamp)
	}
	return(rc)
}

oanda <- fetch_ticks(OANDA_BROKER_ID, PAIR_NAME, FROM_TIME, UNTIL_TIME)
fxcm  <- fetch_ticks(FXCM_BROKER_ID, PAIR_NAME, FROM_TIME, UNTIL_TIME)
#
prices <- as.zoo(fxcm)
#
from_x <- first(index(prices))
until_x <- last(index(prices))

plotTitle <- paste("FXCM", " ", PAIR_NAME, "  ", from_x, " until ", until_x, " ", thisTZ, sep="")
colors=rainbow(ncol(prices))
print(xyplot(prices, 
		col=colors, 
		minor.ticks="minutes", 
		main=plotTitle, 
		type = c('g', 'p','l'), 
		screens = 1, 
		xlab="time", ylab="price")
)

prices <- as.zoo(oanda)
from_x <- first(index(prices))
until_x <- last(index(prices))
plotTitle <- paste("OANDA", " ", PAIR_NAME, "  ", from_x, " until ", until_x, " ", thisTZ, sep="")
colors=rainbow(ncol(prices))
print(xyplot(prices, 
			 col=colors, 
			 minor.ticks="minutes", 
			 main=plotTitle, 
			 type = c('g', 'p','l'), 
			 screens = 1, 
			 xlab="time", ylab="price")
)

prices<-as.zoo(merge.xts(fxcm, oanda))
plotTitle <- paste("BOTH", " ", PAIR_NAME, "  ", from_x, " until ", until_x, " ", thisTZ, sep="")
colors=rainbow(ncol(prices))
print(xyplot(prices, 
			 col=colors, 
			 minor.ticks="minutes", 
			 main=plotTitle, 
			 type = c('g', 'p','l'), 
			 screens = 1, 
			 xlab="time", ylab="price")
)



