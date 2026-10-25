<#
.SYNOPSIS
Turns a folder of saved Run Planner plans (*.runplanner.json) into catalog entry folders.

.DESCRIPTION
For each plan it creates <OutFolder>\<slug>\ with a copy of the plan as plan.runplanner.json and
an entry.json whose title, tags and description come from the file name and the plan. Review the
generated entry.json files before uploading them.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File catalog-import.ps1 -PlansFolder C:\plans -Category perfectrun -Author "Your name"
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$PlansFolder,
    [string]$Category,
    [string]$Author,
    [string]$OutFolder
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$MaxPlanBytes = 1MB
$MaxTags = 8
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
$Questions = 0

# A problem the user can fix: printed as a plain message, never as a stack trace.
function Stop-Import([string]$Message) {
    throw (New-Object System.InvalidOperationException $Message)
}

function Remove-Quotes([string]$Text) {
    if ($null -eq $Text) { return '' }
    return $Text.Trim().Trim('"').Trim("'").Trim()
}

function Read-Answer([string]$Prompt) {
    $script:Questions++
    if ($script:Questions -gt 12) { Stop-Import 'No usable answer was given; nothing was imported.' }
    return (Read-Host $Prompt)
}

function ConvertTo-Slug([string]$Text) {
    $decomposed = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $plain = New-Object System.Text.StringBuilder
    foreach ($character in $decomposed.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne
            [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$plain.Append($character)
        }
    }
    $slug = ($plain.ToString().ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    return $slug
}

function ConvertTo-JsonString([string]$Text) {
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    foreach ($character in $Text.ToCharArray()) {
        switch ($character) {
            '"' { [void]$builder.Append('\"'); continue }
            '\' { [void]$builder.Append('\\'); continue }
            default {
                if ([int]$character -lt 32) {
                    [void]$builder.Append(('\u{0:x4}' -f [int]$character))
                } else {
                    [void]$builder.Append($character)
                }
            }
        }
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Get-Property($Object, [string]$Name) {
    if ($null -eq $Object -or $Object -isnot [System.Management.Automation.PSCustomObject]) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Read-Json([string]$Path) {
    return ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}

# "Event05BladesMel (d5247e87).runplanner.json" -> "Event05 Blades Mel"
function Get-PlanTitle([string]$FileName) {
    $name = $FileName -replace '(?i)\.runplanner\.json$', '' -replace '(?i)\.json$', ''
    $name = ($name -replace '\s*\([0-9a-fA-F]{8}\)\s*$', '').Trim()
    if ($name -notmatch '\s') {
        $name = $name -creplace '(?<=[a-z0-9])(?=[A-Z])', ' ' -creplace '(?<=[A-Z])(?=[A-Z][a-z])', ' '
    }
    $name = ($name -replace '\s+', ' ').Trim()
    if ($name.Length -gt 80) { $name = $name.Substring(0, 80).Trim() }
    return $name
}

function Get-FileSuffixId([string]$FileName) {
    $match = [regex]::Match($FileName, '\(([0-9a-fA-F]{8})\)(?:\.runplanner)?\.json$')
    if ($match.Success) { return $match.Groups[1].Value.ToLowerInvariant() }
    return $null
}

# Every boon the plan takes: each trait offer's selected option, Concave Stone's extra pick,
# Anvil of Fates additions and keepsake-granted traits. Counts authored choices, not a simulation.
function Add-TakenTraits($Node, [System.Collections.Generic.List[string]]$Taken) {
    if ($null -eq $Node) { return }
    if ($Node -is [System.Array]) {
        foreach ($item in $Node) { Add-TakenTraits $item $Taken }
        return
    }
    if ($Node -isnot [System.Management.Automation.PSCustomObject]) { return }

    $kind = Get-Property $Node 'kind'
    $options = Get-Property $Node 'options'
    if ($kind -eq 'traits' -and $null -ne $options) {
        $optionList = @($options)
        foreach ($key in @((Get-Property $Node 'selectedOptionKey'),
                (Get-Property (Get-Property $Node 'concaveStoneResult') 'optionKey'))) {
            if ($key -is [string] -and $key -match '^option([1-3])$') {
                $index = [int]$Matches[1] - 1
                if ($index -lt $optionList.Count) {
                    $traitKey = Get-Property $optionList[$index] 'traitKey'
                    if ($traitKey -is [string]) { $Taken.Add($traitKey) }
                }
            }
        }
    }
    if ($kind -eq 'anvilOfFates') {
        foreach ($traitKey in @(Get-Property $Node 'addedTraitKeys')) {
            if ($traitKey -is [string]) { $Taken.Add($traitKey) }
        }
    }
    foreach ($property in $Node.PSObject.Properties) {
        if ($property.Name -eq 'options') { continue }
        if ($property.Name -in @('jeweledPom', 'experimentalHammer')) {
            $traitKey = Get-Property $property.Value 'traitKey'
            if ($traitKey -is [string]) { $Taken.Add($traitKey) }
        }
        Add-TakenTraits $property.Value $Taken
    }
}

function Test-PlanShape($Plan) {
    if ($Plan -isnot [System.Management.Automation.PSCustomObject]) { return 'it is not a Run Planner plan' }
    $schemaVersion = Get-Property $Plan 'schemaVersion'
    if (($schemaVersion -isnot [int]) -and ($schemaVersion -isnot [long])) {
        return 'it has no schemaVersion, so it is not a saved Run Planner plan'
    }
    if ((Get-Property $Plan 'projectId') -isnot [string]) { return 'it has no projectId' }
    if ((Get-Property $Plan 'catalogVersion') -isnot [string]) { return 'it has no catalogVersion' }
    $route = Get-Property $Plan 'route'
    if ((Get-Property $route 'routeKey') -isnot [string]) { return 'it has no route' }
    if ($null -eq (Get-Property $route 'loadout')) { return 'it has no loadout' }
    return $null
}

function Format-EntryJson([string]$Title, [string]$Description, [string]$CategoryId,
    [string[]]$Tags, [string]$EntryAuthor) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('{')
    $lines.Add('  "title": ' + (ConvertTo-JsonString $Title) + ',')
    $lines.Add('  "description": ' + (ConvertTo-JsonString $Description) + ',')
    $lines.Add('  "category": ' + (ConvertTo-JsonString $CategoryId) + ',')
    if ($Tags.Count -eq 0) {
        $lines.Add('  "tags": [],')
    } else {
        $lines.Add('  "tags": [')
        for ($i = 0; $i -lt $Tags.Count; $i++) {
            $comma = if ($i -lt $Tags.Count - 1) { ',' } else { '' }
            $lines.Add('    ' + (ConvertTo-JsonString $Tags[$i]) + $comma)
        }
        $lines.Add('  ],')
    }
    $lines.Add('  "author": ' + (ConvertTo-JsonString $EntryAuthor))
    $lines.Add('}')
    return ($lines -join "`n") + "`n"
}

function Invoke-Import {
    $scriptFolder = $PSScriptRoot
    $repositoryFolder = Split-Path -Parent $scriptFolder

    $tagsPath = Join-Path $scriptFolder 'catalog-tags.json'
    if (-not (Test-Path -LiteralPath $tagsPath -PathType Leaf)) {
        Stop-Import "catalog-tags.json is missing. Keep it in the same folder as this script ($scriptFolder)."
    }
    $lookup = Read-Json $tagsPath

    # Plans folder
    $PlansFolder = Remove-Quotes $PlansFolder
    while ($PlansFolder -eq '') {
        Write-Host 'Drag the folder with your saved plans (*.runplanner.json) here, then press Enter.'
        $PlansFolder = Remove-Quotes (Read-Answer 'Plans folder')
    }
    if (-not (Test-Path -LiteralPath $PlansFolder -PathType Container)) {
        Stop-Import "Can't find the folder '$PlansFolder'."
    }
    $PlansFolder = (Resolve-Path -LiteralPath $PlansFolder).ProviderPath
    $planFiles = @(Get-ChildItem -LiteralPath $PlansFolder -File |
            Where-Object { $_.Name -like '*.runplanner.json' } | Sort-Object Name)
    if ($planFiles.Count -eq 0) {
        Stop-Import "There are no .runplanner.json files in '$PlansFolder'. Save your plans from Run Planner first."
    }

    # Category
    $categories = @()
    foreach ($candidate in @((Join-Path $repositoryFolder 'categories.json'), (Join-Path $scriptFolder 'categories.json'))) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $categories = @((Read-Json $candidate).categories)
            break
        }
    }
    $Category = Remove-Quotes $Category
    $categoryLabel = $null
    while ($null -eq $categoryLabel) {
        if ($Category -eq '') {
            if ($categories.Count -gt 0) {
                Write-Host ''
                Write-Host 'Categories:'
                for ($i = 0; $i -lt $categories.Count; $i++) {
                    Write-Host ('  {0}. {1}' -f ($i + 1), $categories[$i].label)
                }
                $Category = Remove-Quotes (Read-Answer 'Category number')
            } else {
                $Category = Remove-Quotes (Read-Answer 'Category id (from categories.json)')
            }
        }
        if ($Category -match '^\d+$' -and [int]$Category -ge 1 -and [int]$Category -le $categories.Count) {
            $Category = $categories[[int]$Category - 1].id
        }
        if ($categories.Count -eq 0) {
            if ($Category -match '^[a-z0-9]+(-[a-z0-9]+)*$') { $categoryLabel = $Category }
        } else {
            $match = @($categories | Where-Object { $_.id -eq $Category -or $_.label -eq $Category })
            if ($match.Count -gt 0) { $Category = $match[0].id; $categoryLabel = $match[0].label }
        }
        if ($null -eq $categoryLabel) {
            Write-Host "'$Category' is not a category. Pick one from the list." -ForegroundColor Yellow
            $Category = ''
        }
    }

    # Author
    $Author = ($Author -replace '\s+', ' ').Trim()
    while ($Author -eq '' -or $Author.Length -gt 64) {
        if ($Author.Length -gt 64) { Write-Host 'The author name can be at most 64 characters.' -ForegroundColor Yellow }
        $Author = ((Read-Answer 'Author (who made these plans)') -replace '\s+', ' ').Trim()
    }

    # Output folder
    $OutFolder = Remove-Quotes $OutFolder
    if ($OutFolder -eq '') {
        $repositoryEntries = Join-Path $repositoryFolder 'entries'
        if ((Test-Path -LiteralPath $repositoryEntries -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $repositoryFolder 'categories.json') -PathType Leaf)) {
            $OutFolder = $repositoryEntries
        } else {
            $OutFolder = Join-Path (Split-Path -Parent $PlansFolder) 'catalog-entries'
        }
    }
    if (-not (Test-Path -LiteralPath $OutFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $OutFolder -Force | Out-Null
    }
    $OutFolder = (Resolve-Path -LiteralPath $OutFolder).ProviderPath

    # Entries already in the output folder: their slugs are taken and their plans are not re-added.
    $usedSlugs = @{}
    $existingProjects = @{}
    foreach ($folder in @(Get-ChildItem -LiteralPath $OutFolder -Directory)) {
        $usedSlugs[$folder.Name.ToLowerInvariant()] = $true
        $existingPlan = Join-Path $folder.FullName 'plan.runplanner.json'
        if (Test-Path -LiteralPath $existingPlan -PathType Leaf) {
            $match = [regex]::Match([System.IO.File]::ReadAllText($existingPlan), '"projectId"\s*:\s*"([^"]+)"')
            if ($match.Success) { $existingProjects[$match.Groups[1].Value] = $folder.Name }
        }
    }

    Write-Host ''
    Write-Host "Reading $($planFiles.Count) plan(s) from $PlansFolder"

    # Load and check every plan first, so duplicates can be resolved before anything is written.
    $problems = New-Object System.Collections.Generic.List[string]
    $loaded = New-Object System.Collections.Generic.List[object]
    foreach ($file in $planFiles) {
        if ($file.Length -gt $MaxPlanBytes) {
            $problems.Add("$($file.Name): larger than 1 MB, which the catalog does not accept.")
            continue
        }
        try {
            $plan = Read-Json $file.FullName
        } catch {
            $problems.Add("$($file.Name): not a readable plan file (it is not valid JSON).")
            continue
        }
        $shapeProblem = Test-PlanShape $plan
        if ($null -ne $shapeProblem) {
            $problems.Add("$($file.Name): $shapeProblem.")
            continue
        }
        $identity = $plan.projectId
        $loaded.Add([pscustomobject]@{
                File     = $file
                Plan     = $plan
                Identity = $identity
                IsCopy   = ($file.Name -match '(?i)\(copy\)')
            })
    }

    # Copies of one plan share its projectId (and file-name id): keep one, preferring the original.
    $skipped = New-Object System.Collections.Generic.List[string]
    $chosen = New-Object System.Collections.Generic.List[object]
    foreach ($group in ($loaded | Group-Object Identity)) {
        $ordered = @($group.Group | Sort-Object @{ Expression = 'IsCopy' }, @{ Expression = { $_.File.Name } })
        $keep = $ordered[0]
        for ($i = 1; $i -lt $ordered.Count; $i++) {
            $skipped.Add("$($ordered[$i].File.Name): same plan as $($keep.File.Name).")
        }
        if ($existingProjects.ContainsKey($keep.Identity)) {
            $skipped.Add("$($keep.File.Name): already added as $($existingProjects[$keep.Identity]).")
            continue
        }
        $chosen.Add($keep)
    }

    $categoryTags = @($Category, (ConvertTo-Slug $categoryLabel))
    $created = New-Object System.Collections.Generic.List[string]
    foreach ($item in ($chosen | Sort-Object { $_.File.Name })) {
        $file = $item.File
        $plan = $item.Plan
        $loadout = $plan.route.loadout
        $routeKey = $plan.route.routeKey
        $route = Get-Property $lookup.routes $routeKey
        $routeLabel = if ($null -ne $route) { $route.label } else { $routeKey }

        $weaponKey = Get-Property $loadout 'weaponKey'
        if ($null -eq $weaponKey -and $null -ne $route) { $weaponKey = Get-Property $route 'fixedWeaponKey' }
        $weapon = if ($weaponKey -is [string]) { Get-Property $lookup.weapons $weaponKey } else { $null }
        $aspectKey = Get-Property $loadout 'aspectKey'
        $aspect = if ($aspectKey -is [string]) { Get-Property $lookup.aspects $aspectKey } else { $null }

        # Main gods: Olympians with at least two boons taken, most boons first, then by name.
        $taken = New-Object System.Collections.Generic.List[string]
        Add-TakenTraits $plan.route $taken
        $godCounts = @{}
        foreach ($traitKey in $taken) {
            foreach ($god in @(Get-Property $lookup.boons $traitKey)) {
                if ($god -is [string]) { $godCounts[$god] = 1 + [int]$godCounts[$god] }
            }
        }
        $mainGods = @($godCounts.GetEnumerator() | Where-Object { $_.Value -ge 2 } |
                Sort-Object @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Name' } |
                ForEach-Object { $_.Name })

        $tags = New-Object System.Collections.Generic.List[string]
        $candidates = @()
        if ($null -ne $weapon) { $candidates += $weapon.tag }
        if ($null -ne $aspect) { $candidates += $aspect.tag }
        $candidates += $mainGods
        foreach ($tag in $candidates) {
            if ($tags.Count -ge $MaxTags) { break }
            if ($tag -in $categoryTags -or $tags.Contains($tag) -or $tag.Length -gt 24) { continue }
            $tags.Add($tag)
        }

        $title = Get-PlanTitle $file.Name
        if ($title -eq '') { $title = 'Untitled plan' }
        $words = @()
        if ($null -ne $aspect) { $words += $aspect.name }
        if ($null -ne $weapon) { $words += $weapon.name }
        $words += $routeLabel
        $description = (($words -join ' ') + ' run.')
        if ($description.Length -gt 200) { $description = $description.Substring(0, 200) }

        $baseSlug = ConvertTo-Slug $title
        if ($baseSlug -eq '') { $baseSlug = 'plan' }
        if ($baseSlug.Length -gt 60) { $baseSlug = $baseSlug.Substring(0, 60).Trim('-') }
        $slug = $baseSlug
        $suffix = 2
        while ($usedSlugs.ContainsKey($slug)) { $slug = "$baseSlug-$suffix"; $suffix++ }
        $usedSlugs[$slug] = $true

        try {
            $entryFolder = Join-Path $OutFolder $slug
            New-Item -ItemType Directory -Path $entryFolder -Force | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $entryFolder 'plan.runplanner.json') -Force
            $entryJson = Format-EntryJson $title $description $Category @($tags) $Author
            [System.IO.File]::WriteAllText((Join-Path $entryFolder 'entry.json'), $entryJson, $Utf8NoBom)
        } catch {
            $problems.Add("$($file.Name): could not write $slug ($($_.Exception.Message)).")
            continue
        }
        $created.Add("$slug  [$($tags -join ', ')]")
    }

    Write-Host ''
    if ($created.Count -gt 0) {
        Write-Host "Created $($created.Count) entr$(if ($created.Count -eq 1) { 'y' } else { 'ies' }) in $OutFolder" -ForegroundColor Green
        foreach ($line in $created) { Write-Host "  $line" }
    } else {
        Write-Host 'No entries were created.' -ForegroundColor Yellow
    }
    if ($skipped.Count -gt 0) {
        Write-Host ''
        Write-Host "Skipped $($skipped.Count) duplicate(s):"
        foreach ($line in $skipped) { Write-Host "  $line" }
    }
    if ($problems.Count -gt 0) {
        Write-Host ''
        Write-Host "$($problems.Count) file(s) could not be added:" -ForegroundColor Yellow
        foreach ($line in $problems) { Write-Host "  $line" -ForegroundColor Yellow }
    }
    if ($created.Count -gt 0) {
        Write-Host ''
        Write-Host 'Next steps:'
        Write-Host '  1. Open each new folder and check entry.json: the title, description and tags are'
        Write-Host '     guesses from the file name and plan, so edit them as you like.'
        Write-Host '  2. On GitHub, open the catalog repository, go to the entries folder and use'
        Write-Host '     "Add file" > "Upload files" to drag the new folders in, then propose the change;'
        Write-Host '     or commit them in your checkout and open a pull request.'
    }
    return [int]($created.Count -eq 0 -and $problems.Count -gt 0)
}

try {
    exit (Invoke-Import)
} catch [System.InvalidOperationException] {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
} catch {
    Write-Host "Something went wrong: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
