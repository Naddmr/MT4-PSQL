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

unit uPQWriterDefinitions;

{$mode objfpc}{$H+}

interface

uses
	cMem,
        Classes,
        Windows,
        SysUtils,
        DateUtils;
type
// Representation of a tick row in MQL
TMQLTickRow = packed record
        time	: INT64;
        bid,
        ask,
        last	: Double;
        volume	: LongInt;
end;
pMQLTickRow = ^TMQLTickRow;
// A tick row with milliseconds
TSQLTickRow = packed record
        pairID		: Integer;
        MQLTick		: TMQLTickRow;
        localTime	: TDateTime;
        TickTime	: TDateTime;
        TickCounter	: Integer;
end;
pSQLTickRow = ^TSQLTickRow;
//
// A broker definition row
TSQLBrokerRow = packed record
        broker_id	: Integer;
        is_demo		: boolean;
        broker_name	: AnsiString;
        broker_timezone	: AnsiString;
end;
pSQLBrokerRow = ^TSQLBrokerRow;
//
// A pair definition row
TSQLPairRow = packed record
        pair_id		: Integer;
        broker_id	: Integer;
        pair_name	: AnsiString;
        point		: Double;
        Digits		: Double;
end;
pSQLPairRow = ^TSQLPairRow;
//
TFiFoPointer = packed record
        read_idx	: DWORD;
        write_idx	: DWORD;
end;
//
const
	BROKER_SHAREMEM_SUFFIX	=	'_BROKERS';
        PAIR_SHAREMEM_SUFFIX	=	'_PAIRS';
        TICKS_SHAREMEM_SUFFIX	=	'_TICKS';
        SEM_MUTEX_PREFIX	=	'SEM_';

procedure Log(AMessage: WideString);
procedure Log(AMessage: WideString; AArgs: array of const);

implementation
// log a message to the debug monitor
procedure Log(AMessage: WideString);
begin
	OutputDebugStringW( PWideChar(AMessage) );
end;

// log a formatted message to the debug monitor
procedure Log(AMessage: WideString; AArgs: array of const);
begin
	Log(Format(AMessage, AArgs));
end;

end.

