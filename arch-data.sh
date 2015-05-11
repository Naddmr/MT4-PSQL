#!/bin/bash
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
# Server connection parameters
DBNAM="mtforex"
DBSRV="extern"
DBUSR="postgres"
DBPWD=""
DBPRT="5432"
#
# Where is the PSQL binary located and how is it called?
PSQL="psql -q -n -d $DBNAM -h $DBSRV -U $DBUSR -p $DBPRT"
#
# Directory parameters - where to archive the data?
BASEDIR="/home/dwl/pgticks/"
# What is the base file name of the tickdata exports?
# (the timestamp will be appended!)
BASENAME="TICKDATA"
#
# What is the extension said file name?
BASEEXT=".csv"
#
# Retain data for X hours or days or whatever ...
HOLDINTERVAL="7 days"
#
# Get the export date into a variable to build a unique filename later
EXPDATE=`date +"%Y-%m-%d-%H-%M"`
#
# Get the last keep time into a variable to ensure consistent snapshots
KEEPDATE=`$PSQL -c "copy (select now() - interval '$HOLDINTERVAL') to stdout"`
#
# Fetch the list of brokers from SQL and store it into a README file
#
BROKERQUERY="copy (select broker_id, '\"' || brokername || '\"' from t_mt4_brokers) to stdout;"
echo "$BROKERQUERY" | $PSQL >"$BASEDIR/Brokerlist.txt"
#
# Loop over all brokers from the server
echo "$BROKERQUERY" | $PSQL | while read b_id b_name ; do 
	echo "Exporting data from broker $b_name (ID=$b_id) ($EXPDATE)"
	#
	# Loop over all pairs from the current broker
	PAIRQUERY="copy (select pair_id, pairname from t_mt4_pairdata where broker_id=$b_id ) to stdout;"
	echo "$PAIRQUERY" | $PSQL | while read p_id p_name ; do
		# get the number of rows to export
		ROWCOUNT=`$PSQL -c "copy (select count(*) from t_mt4_ticks where pair_id=$p_id and ttimestamp<timestamp '$KEEPDATE') to stdout"`
		if [ $ROWCOUNT -gt 0 ] ; then 
			PAIRDIR="$BASEDIR$b_id/$p_name"
			test -d $PAIRDIR || mkdir -p "$PAIRDIR"
			FN="$BASENAME-$KEEPDATE-$EXPDATE$BASEEXT"
			echo "Exporting $p_name (ID=$p_id) from $b_name (ID=$b_id) into $FN ($ROWCOUNT until $KEEPDATE)"
			EXPQUERY=`cat <<EOF
			copy (
				select 
					* 
				from 
					t_mt4_ticks 
				where 
					pair_id=$p_id and
					ttimestamp<timestamp '$KEEPDATE'
			) to stdout with csv header;
EOF`
			#
			# This overwrites any existing file 
			(echo "$EXPQUERY" | $PSQL && echo "\\." ) | 7z a -si -t7z -m0=lzma -mx=9 -mfb=64 -md=32m -ms=on "$PAIRDIR/$FN.7z"
			#
			# If comment the above step out you can also issue a
			#
			# (echo "$EXPQUERY" | $PSQL && echo "\\." ) | psql -d $DWHDB -U $DWHUSER -h $DWHHOST -c "copy into t_mt4_ticks from stdin with csv header" 
			#
			# to import the tick table directly into a DWH server. If you leave the line using "7z" 
			# active you have both ways open.
			
			#
			# Prepare the deletion of the data in the database
			DELQUERY=`cat <<EOF
				delete from t_mt4_ticks
				where 
					pair_id=$p_id and
					ttimestamp<timestamp '$KEEPDATE'
	
EOF`
			echo "Deleting $p_name (ID=$p_id) from $b_name (ID=$b_id) until $KEEPDATE"
			echo "$DELQUERY" | $PSQL
		else
			echo "In $p_name (ID=$p_id) from $b_name (ID=$b_id) are no rows to export - doing nothing"
		fi
	done
done
#
# update statistics 
echo "Vacuuming tick table ..."
$PSQL -c "vacuum analyze t_mt4_ticks"
#
echo "done ..."


