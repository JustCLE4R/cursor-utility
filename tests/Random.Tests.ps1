# Run with: Invoke-Pester .\tests   (Pester 3.4+)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "..\modules\Random.ps1")

Describe "Get-NaturalRandom" {

    $samples = 1..2000 | ForEach-Object { Get-NaturalRandom 10 20 }

    It "returns integers" {
        foreach ($value in $samples) {
            $value -is [int] | Should Be $true
        }
    }

    It "stays within [Min, Max]" {
        ($samples | Measure-Object -Minimum).Minimum -ge 10 | Should Be $true
        ($samples | Measure-Object -Maximum).Maximum -le 20 | Should Be $true
    }

    It "centres on the middle of the range" {
        $average = ($samples | Measure-Object -Average).Average

        ($average -gt 14.5 -and $average -lt 15.5) | Should Be $true
    }

    It "lands near the middle more often than at the edges" {
        $middle = @($samples | Where-Object { $_ -ge 14 -and $_ -le 16 }).Count
        $edges = @($samples | Where-Object { $_ -le 11 -or $_ -ge 19 }).Count

        $middle -gt $edges | Should Be $true
    }

    It "returns Min when Min equals Max" {
        Get-NaturalRandom 5 5 | Should Be 5
    }

    It "works with the corner delay range" {
        foreach ($i in 1..200) {
            $value = Get-NaturalRandom 700 2200
            ($value -ge 700 -and $value -le 2200) | Should Be $true
        }
    }
}
