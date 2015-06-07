{
  Author: Sven Barth
  Date: 07-18-2010
  Description: Implementation of OutputDebugString which bypasses writing the
               message to an attached debugger, but writes it directly into the
               shared message file. Based on implementation of kernel32/debug.c
               of ReactOS
  License: The license depends on whether this code fragment which is a modified
           Pascal translation of the code mentioned above is considered a
           derived work.
           1) it is a derived work: GPLv2
           2) it is not a derived work: use it as you want (but you might honor
              the ReactOS project as original copyright holder somehow)
}
unit DebugMonitor;

{$mode objfpc}{$H+}

interface

procedure OutputToDebugMonitor(const aStr: String);

implementation

uses
  windows, jwawinnt;

const
  DBWinMutex: WideString = 'DBWinMutex';
  DBWinBufferReady: WideString = 'DBWIN_BUFFER_READY';
  DBWinDataReady: WideString = 'DBWIN_DATA_READY';
  DBWinBuffer: WideString = 'DBWIN_BUFFER';
  PageSize = $1000; // defined in mmtypes.h

procedure OutputToDebugMonitor(const aStr: String);
type
  TDBMonBuffer = packed record
    ProcessId: DWord;
    Buffer: array[0..0] of Char;
  end;
  PDBMonBuffer = ^TDBMonBuffer;
var
  bufferready, dataready, buffer, mutex: THandle;
  pbuffer: PDBMonBuffer;
  usesize: Integer;
  s: String;
  tmp: PByte;
begin
  bufferready := 0;
  dataready := 0;
  buffer := 0;
  mutex := 0;
  pbuffer := Nil;
  s := aStr;

  (* first try to open the mutex, if that fails call OutputDebugString, which
    will create that for us (we can't do that ourselves easily) *)
  mutex := OpenMutexW(SYNCHRONIZE or READ_CONTROL or MUTANT_QUERY_STATE, True,
             PWideChar(DBWinMutex));
  if mutex = 0 then begin
    OutputDebugStringA(PChar(aStr));
    Exit;
  end;

  (* this one-time repeat is just a good hidden GOTO :P *)
  repeat
    WaitForSingleObject(mutex, INFINITE);

    buffer := OpenFileMappingW(SECTION_MAP_WRITE, False,
                PWideChar(DBWinBuffer));
    if buffer = 0 then
      Break;

    pbuffer := MapViewOfFile(buffer, SECTION_MAP_READ or SECTION_MAP_WRITE, 0,
                 0, 0);
    if pbuffer = Nil then
      Break;

    bufferready := OpenEventW(SYNCHRONIZE, False, PWideChar(DBWinBufferReady));
    if bufferready = 0 then
      Break;

    dataready := OpenEventW(EVENT_MODIFY_STATE, False, PWideChar(DBWinDataReady));
  until True;

  if dataready = 0 then
    ReleaseMutex(mutex)
  else begin
    repeat
      if WaitForSingleObject(bufferready, 10000) <> WAIT_OBJECT_0 then
        Break;

      pbuffer^.ProcessId := GetCurrentProcessId;

      if Length(s) > (PageSize - SizeOf(DWord) - 1) then
        usesize := PageSize - SizeOf(DWord) - 1
      else
        usesize := Length(aStr);

      Move(s[1], pbuffer^.Buffer, usesize);
      (* write the terminating zero *)
      tmp := @pbuffer^.Buffer + usesize + 1;
      tmp^ := 0;

      SetEvent(dataready);

      s := Copy(s, usesize, Length(s) - usesize);
    until Length(s) = 0;
  end;

  (* Clean up *)
  if bufferready <> 0 then
    CloseHandle(bufferready);
  if pbuffer <> Nil then
    UnmapViewOfFile(pbuffer);
  if buffer <> 0 then
    CloseHandle(buffer);
  if dataready <> 0 then begin
    CloseHandle(dataready);
    ReleaseMutex(mutex);
  end;
  if mutex <> 0 then
    CloseHandle(mutex);
end;

end.

