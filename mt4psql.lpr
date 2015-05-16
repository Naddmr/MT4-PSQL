{
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
}

library mt4psql;

{$mode objfpc}{$H+}

uses
       cMem,
       Classes,
       Windows,
       SysUtils,
       UpqClass,
       uPQDispatcher,
       uPQWriterDefinitions;

function pqInit(
   	pBrokerTimezone		: pWideChar;
        pMachineTimezone	: pWideChar;
  	pEAName    		: PWideChar;
        pPairName 		: PWideChar;
        pBrokerName		: PWideChar;
        pIsDemo			: DWORD;
        pTimeframe		: Integer;
        pPoint			: Double;
        pDigits			: Double;
        pPollingInterval	: DWORD;
        pDBHostname		: pWideChar;
        pDBHostPort		: Integer;
        pDBName			: pWideChar;
        pDBUsername		: pWideChar;
        pDBPassword		: pWideChar;
        pMaxRetries		: DWORD
) : LongInt; stdcall;
var
	 hdl	  : LongInt;
begin
     hdl:=LongInt(
     		PQDispatcher.Create(
                	pBrokerTimezone,
                        pMachineTimezone,
     			pEAName,
                        pPairName,
                        pBrokerName,
                        pIsDemo,
                        pTimeframe,
                        pPoint,
                        pDigits,
                        pPollingInterval,
                        pDBHostname,
                        pDBHostPort,
                        pDBName,
                        pDBUsername,
                        pDBPassword,
                        pMaxRetries
     		)
     );
     exit(hdl);
end;

procedure pqDeInit(pHdl		: LongInt) ; stdcall;
begin
        if (PQDispatcher(pHdl)<>NIL) then
     		PQDispatcher(pHdl).free;
end;

procedure DispatchTick(
          pHdl	    	  	: LongInt;
          pTick			: pMQLTickRow
); stdcall;
var
         nTick			: pSQLTickRow;
begin
     	// Copy the tick value into a heap variable
     	// and enqueue the values ...
     	nTick:=New(pSQLTickRow);
     	nTick^.MQLTick:=pTick^;
     	// store an additional timestamp of the local time
     	// in the tick row to derive the milliseconds from there.
     	nTick^.ts:=DateTimeToTimeStamp(Now);
     	PQDispatcher(pHdl).DispatchTick(nTick);
end;

function isValidHandle(
          pHdl			: LongInt
):Integer;
var
        rc	: Integer;
begin
     	// if (PQDispatcher(pHdl)<>NIL) then
        rc:=PQDispatcher(pHdl).GetisValid();
     	log('isValidHandle: rc=%d ...', [rc]);
     	exit( rc );
end;

exports
	pqInit,
	pqDeInit,
	DispatchTick,
	isValidHandle
;

begin

end.

