/*
Exports tick data into a PostgreSQL database
    Copyright (C) 2015  Naddmr

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#property copyright "2014 Naddmr GPLV3"
#property link "http://www.forexfabrik.de"
#property indicator_chart_window 

#include <stdlib.mqh>

extern string	DBConfigFileName="PQWriter_DB_Config_FXCM.set";
extern bool 	isDebug=false;
extern string	LabelText="SQL-EXPORT";
extern string	LabelSize=80;

// 
static string	BrokerTimezone="UTC";
static string	LocalTimezone="Europe/Berlin";
static string	DBHostName="192.168.186.199";
static int	DBPortnumber=5432;
static string 	DBDatabaseName="mtforex";
static string	DBUserName="postgres";
static string 	DBPassword="";
static int	DBMaxRetries=100;
static int 	PollingInterval=100;

#import "mt4psql.dll"
	int pqInit(
		string	pBrokerTimezone,
		string	pMachineTimezone,
		string	pEAName,
		string	pPairName,
		string	pBrokerName,
		int 	pIsDemo,
		int	pTimeframe,
		double	pPoint,
		double	pDigits,
		int	pPollingInterval,
		string	pDBHostname,
		int	pDBHostPort,
		string	pDBName,
		string	pDBUsername,
		string	pDBPassword,
		int	pDBMaxRetries
	);
	//
	void pqDeInit(int pHdl);
	//
	void DispatchTick(
		int pHdl,
		MqlTick &pTick
	);
	int isValidHandle(int pHdl);
#import
static MqlTick this_tick, last_tick;
static bool isInitialized=false;
static bool isConfigRead=false;
static int pqHandle=0;
static string pName="";
void init() {
	pName=WindowExpertName();
	// Read setup file from TerminalPath() to get the DB connection parameters
	// A reconfiguration during a recompile might make the PQWriter fail if default
	// values are loaded.
	string fName=DBConfigFileName;
	Print("init: Opening \"" + fName + "\" to get Database connection parameters ..." );
	int fh=FileOpen(fName, FILE_READ|FILE_TXT);
	if (fh!=INVALID_HANDLE) {
		while (!FileIsEnding(fh)) {
			string s=FileReadString(fh);
			// Ignore comments 
			if (StringFind(s, "#")==1) 
				continue;
			string p[];
			int k=StringSplit(s, StringGetChar("=",0), p);
			if (k!=2) 
				continue;
			p[0]=StringTrimLeft(StringTrimRight(p[0]));
			p[1]=StringTrimLeft(StringTrimRight(p[1]));
			if (p[0]=="BrokerTimezone") 
				BrokerTimezone=p[1];
			if (p[0]=="LocalTimezone") 
				LocalTimezone=p[1];
			if (p[0]=="DBHostName") 
				DBHostName=p[1];
			if (p[0]=="DBPortnumber") 
				DBPortnumber=StringToInteger(p[1]);
			if (p[0]=="DBDatabaseName") 
				DBDatabaseName=p[1];
			if (p[0]=="DBUserName") 
				DBUserName=p[1];
			if (p[0]=="DBPassword") 
				DBPassword=p[1];
			if (p[0]=="DBMaxRetries") 
				DBMaxRetries=StringToInteger(p[1]);
			if (p[0]=="PollingInterval") 
				PollingInterval=StringToInteger(p[1]);
		}
		FileClose(fh);
		Print("init: BrokerTimezone=\"" + BrokerTimezone + "\"");
		Print("init: LocalTimezone=\"" + LocalTimezone + "\"");
		Print("init: DBHostName=\"" + DBHostName + "\"");
		Print("init: DBPortnumber=\"" + DBPortnumber + "\"");
		Print("init: DBDatabaseName=\"" + DBDatabaseName + "\"");
		Print("init: DBUserName=\"" + DBUserName + "\"");
		Print("init: DBPassword=\"" + DBPassword + "\"");
		Print("init: DBMaxRetries=\"" + DBMaxRetries + "\"");
		Print("init: PollingInterval=\"" + PollingInterval + "\"");
		isConfigRead=true;
		if (ObjectFind(pName)<0) {
			ObjectCreate(pName, OBJ_LABEL, 0, 0, 0);
		}
		ObjectSetText(pName, LabelText, LabelSize, "Arial", Red);
		ObjectSet(pName, OBJPROP_BACK, true);
		ObjectSetInteger(0, pName, OBJPROP_SELECTABLE, false);
	} else {
		int err=GetLastError();
		Print("init: ERROR - could not open \"" + fName + "\" because of: " + err + " " + ErrorDescription(err) );
	}
}

void deinit() {
	if (pqHandle!=0) {
		pqDeInit(pqHandle);
	}
	ObjectDelete(pName);
}

void start() {
	static bool isSQLConnected=false;
	if (!isConfigRead) 
		return;
	if (!isSQLConnected) {
		// during startup of the terminal the AccountCompany() and 
		// other variables are not initialized properly.
		// So we have to wait until the startup is complete.
		if (AccountCompany()!="") {
			string dbPar="\"" + DBHostName + "://" + DBUserName + "@" + DBDatabaseName + "\"";
			Print("start: Establishing connection to " + dbPar );
			pqHandle=pqInit(
				BrokerTimezone,
				LocalTimezone,
				"PQ_Writer",
				Symbol(),
				AccountCompany(),
				IsDemo(),
				Period(),
				Point,
				Digits,
				PollingInterval,
				DBHostName,
				DBPortnumber,
				DBDatabaseName,
				DBUserName,
				DBPassword,
				DBMaxRetries
			);
			Print("start: Checking connection to " + dbPar );
			// Retry connection "if (!IsSQLConnected)"
			isSQLConnected=(isValidHandle(pqHandle)!=0);
			Print("start: Connectionhandle is " + pqHandle + " isValidHandle=" + isSQLConnected );
			if (!isSQLConnected) {
				Print("start: NOT CONNECTED! Cleaning up handle=" + pqHandle );
				pqDeInit(pqHandle);
				pqHandle=0;
				Sleep(PollingInterval);
			} else {
				if (ObjectFind(pName)>=0) {
					ObjectSetText(pName, LabelText, LabelSize, "Arial", LightGray);
				}
			}
		}
	} else {
		
		if (isInitialized) {
			if (isDebug) {
				uint startT=GetTickCount();
			}
			if (SymbolInfoTick(Symbol(), this_tick)) {
				// Filter duplicate ticks during the same second.
				if (
					(this_tick.time!=last_tick.time) ||
					(this_tick.bid!=last_tick.bid) ||
					(this_tick.ask!=last_tick.ask) ||
					(this_tick.last!=last_tick.last) ||
					(this_tick.volume!=last_tick.volume)
				) {
					if (isDebug) {
						uint writeT=GetTickCount();
					}
					DispatchTick(pqHandle, this_tick);
				}
			}
			
		}
		last_tick=this_tick;
		isInitialized=true;
		if (isDebug) {
			uint endT=GetTickCount();
			Print("Writing took " + (endT-writeT) + " msecs, start took " + (endT-startT) + " msecs" );
		}
	}
}
