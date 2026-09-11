@ECHO OFF
SET LIBDIR=%ELMER_HOME%/bin
SET INCLUDE=%ELMER_HOME%/share/elmersolver/include

SET LD="%ELMER_HOME%/stripped_gfortran/bin/"

REM SET CMD=%LD% -shared %* -L"%LIBDIR%" -L"%ELMER_HOME%/bin" -lelmersolver
SET CMD=%LD%  -fallow-argument-mismatch  -shared %* -L"C:/Program Files/Elmer 26.2.1-Release/lib/elmersolver" -L"%LIBDIR%" -lelmersolver
echo %cmd%
%cmd%
