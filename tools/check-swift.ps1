# Lexer-level sanity check for the Swift sources.
#
#   powershell -ExecutionPolicy Bypass -File ios\tools\check-swift.ps1
#
# WHAT THIS IS: a tokenizer that walks each .swift file, skipping string literals, multi-line
# strings, line comments and block comments, and verifies that (), [], {} nest and close
# correctly; it also flags a handful of mistakes that are common in code written without a
# compiler and that a real build would reject.
#
# WHAT THIS IS NOT: a compiler. Swift has type checking, overload resolution, protocol
# conformance and macro expansion that cannot be verified outside Xcode. A clean run here means
# "no obvious lexical breakage", not "this compiles". Only `xcodebuild` can say that.
#
# ASCII-only on purpose: Windows PowerShell 5.1 parses a BOM-less script as ANSI.

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ios = Split-Path -Parent $here
$sourceDir = Join-Path $ios 'DaysEngine'

$files = Get-ChildItem -Path $sourceDir -Filter '*.swift' -Recurse -File
if (-not $files -or $files.Count -eq 0) { throw "No .swift files found under $sourceDir" }

$problems = New-Object System.Collections.Generic.List[string]
$totals = @{ files = 0; lines = 0; opens = 0; closes = 0 }

foreach ($file in $files) {
    $totals.files++
    $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $name = $file.Name
    $totals.lines += ($text -split "`n").Count

    $stack = New-Object System.Collections.Generic.Stack[string]
    $line = 1
    $i = 0
    $n = $text.Length

    # Tracks whether the front of a line has been seen, for the "operator on its own line" check.
    $lineStart = 0

    while ($i -lt $n) {
        $c = $text[$i]

        if ($c -eq "`n") { $line++; $i++; $lineStart = $i; continue }

        # line comment
        if ($c -eq '/' -and $i + 1 -lt $n -and $text[$i + 1] -eq '/') {
            while ($i -lt $n -and $text[$i] -ne "`n") { $i++ }
            continue
        }

        # block comment (nesting, as Swift allows)
        if ($c -eq '/' -and $i + 1 -lt $n -and $text[$i + 1] -eq '*') {
            $depth = 1
            $i += 2
            while ($i -lt $n -and $depth -gt 0) {
                if ($text[$i] -eq '/' -and $i + 1 -lt $n -and $text[$i + 1] -eq '*') { $depth++; $i += 2; continue }
                if ($text[$i] -eq '*' -and $i + 1 -lt $n -and $text[$i + 1] -eq '/') { $depth--; $i += 2; continue }
                if ($text[$i] -eq "`n") { $line++ }
                $i++
            }
            if ($depth -ne 0) { $problems.Add("$name : unterminated block comment") }
            continue
        }

        # multi-line string literal
        if ($c -eq '"' -and $i + 2 -lt $n -and $text[$i + 1] -eq '"' -and $text[$i + 2] -eq '"') {
            $i += 3
            while ($i + 2 -lt $n) {
                if ($text[$i] -eq "`n") { $line++ }
                if ($text[$i] -eq '"' -and $text[$i + 1] -eq '"' -and $text[$i + 2] -eq '"') { $i += 3; break }
                $i++
            }
            continue
        }

        # single-line string literal, honouring \ escapes and \( interpolation
        if ($c -eq '"') {
            $j = $i + 1
            $closed = $false
            while ($j -lt $n) {
                if ($text[$j] -eq '\') { $j += 2; continue }
                if ($text[$j] -eq "`n") { break }
                if ($text[$j] -eq '"') { $closed = $true; $j++; break }
                $j++
            }
            if (-not $closed) {
                $problems.Add("$name line ${line}: string literal is not closed on one line")
            }
            $i = $j
            continue
        }

        if ($c -eq '(' -or $c -eq '[' -or $c -eq '{') {
            $stack.Push($c)
            $totals.opens++
            $i++
            continue
        }

        if ($c -eq ')' -or $c -eq ']' -or $c -eq '}') {
            $totals.closes++
            $expected = switch ($c) { ')' { '(' } ']' { '[' } '}' { '{' } }
            if ($stack.Count -eq 0) {
                $problems.Add("$name line ${line}: closing '$c' with nothing open")
            } else {
                $open = $stack.Pop()
                if ($open -ne $expected) {
                    $problems.Add("$name line ${line}: closing '$c' does not match opening '$open'")
                }
            }
            $i++
            continue
        }

        $i++
    }

    if ($stack.Count -gt 0) {
        $unclosed = ($stack.ToArray() -join ' ')
        $count = $stack.Count
        $problems.Add("$name : $count unclosed delimiter(s): $unclosed")
    }

    # Patterns a real build rejects outright, worth catching before CI spends ten minutes.
    if ($text -match 'import\s+SwiftUI' -and $text -match 'UIApplication\.shared' -and $text -notmatch 'import\s+UIKit') {
        $problems.Add("$name : uses UIApplication.shared without 'import UIKit'")
    }
    if ($text -match 'MKWebView') {
        $problems.Add("$name : 'MKWebView' looks like a typo for WKWebView")
    }
}

Write-Host ("Files: {0}   Lines: {1}   Delimiters: {2} open / {3} close" -f `
    $totals.files, $totals.lines, $totals.opens, $totals.closes)

Write-Host ''
Write-Host 'Swift source files checked:'
foreach ($file in $files) {
    Write-Host ("  {0,-28} {1,6} bytes  {2,5} lines" -f $file.Name, $file.Length, (($file | Get-Content).Count))
}

Write-Host ''
if ($problems.Count -eq 0) {
    Write-Host 'LEXICAL CHECK: PASS - delimiters balanced, no broken literals.' -ForegroundColor Green
    Write-Host 'NOTE: this is not a compile. Only xcodebuild can verify the Swift.' -ForegroundColor Yellow
    exit 0
}

Write-Host ("LEXICAL CHECK: FAIL - {0} problem(s)" -f $problems.Count) -ForegroundColor Red
foreach ($problem in $problems) { Write-Host "  $problem" }
exit 1
