# ============================================================
# Natural randomness
# ============================================================

$Random = New-Object System.Random

# Normally distributed value (Box-Muller) clamped to [Min, Max].
# Most results land near the middle, with occasional outliers,
# which feels more human than a flat uniform range.
function Get-NaturalRandom {
    param(
        [double]$Min,
        [double]$Max
    )

    $mean = ($Min + $Max) / 2
    $stdDev = ($Max - $Min) / 6

    $u1 = 1.0 - $Random.NextDouble()
    $u2 = $Random.NextDouble()
    $normal = [Math]::Sqrt(-2.0 * [Math]::Log($u1)) * [Math]::Sin(2.0 * [Math]::PI * $u2)

    $value = $mean + ($stdDev * $normal)

    return [int][Math]::Max($Min, [Math]::Min($Max, $value))
}
