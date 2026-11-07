# Установщик cc — переключатель сервисов для Claude Code (Windows / PowerShell)
# Что делает:
#   1) ставит Claude Code, если его нет;
#   2) кладёт команду cc в %USERPROFILE%\.local\bin (та же папка, куда ставится claude);
#   3) отключает экран входа в аккаунт Anthropic при первом запуске (он не нужен для сторонних сервисов);
#   4) предлагает сразу добавить первый сервис.
# Общий ~/.claude/settings.json не меняется. Повторный запуск безопасен (обновляет cc, профили не трогает).

& {
  $ErrorActionPreference = 'Stop'
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

  $Root = Join-Path $env:USERPROFILE '.claude-profiles'
  $Bin  = Join-Path $env:USERPROFILE '.local\bin'
  function Say($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c }

  Say ''
  Say '  === Установка cc: Claude Code + любые сервисы ===' Cyan
  Say ''

  # 1. Claude Code
  $claude = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue
  if (-not $claude -and -not (Test-Path (Join-Path $Bin 'claude.exe'))) {
    Say '  [1/3] Claude Code не найден — устанавливаю (из РФ на этом шаге нужен VPN)...' Yellow
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex"
    if (-not (Test-Path (Join-Path $Bin 'claude.exe'))) {
      Say '  Не получилось поставить Claude Code. Включи VPN и запусти установщик ещё раз.' Red
      return
    }
  } else {
    Say '  [1/3] Claude Code уже установлен' Green
  }

  # 2. Команда cc
  New-Item -ItemType Directory -Force $Root | Out-Null
  New-Item -ItemType Directory -Force $Bin  | Out-Null
  $ccSource = @'
# cc — быстрый переключатель сервисов (провайдеров) для Claude Code
#
#   cc                 меню: выбрать сервис и запустить Claude Code
#   cc tooken          сразу запустить нужный профиль (так же работает claude-tooken)
#   cc tooken -c       продолжить прошлый диалог, но уже через другой сервис
#   cc add             добавить сервис (Tooken, OpenRouter или любой свой)
#   cc list            список профилей
#   cc test            проверить все профили (ключ, модель, остаток токенов)
#   cc model ИМЯ       сменить модель        cc key ИМЯ   сменить ключ
#   cc edit ИМЯ        открыть профиль       cc rm ИМЯ    удалить профиль
#
# Профиль = обычный файл настроек Claude Code: %USERPROFILE%\.claude-profiles\ИМЯ.json
# Запуск идёт через "claude --settings профиль.json", общий ~/.claude/settings.json не меняется.

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$Root     = Join-Path $env:USERPROFILE '.claude-profiles'
$Bin      = Join-Path $env:USERPROFILE '.local\bin'
$LastFile = Join-Path $Root '.last'
$Utf8     = New-Object System.Text.UTF8Encoding $false
$Reserved = @('add','list','ls','rm','remove','del','key','model','test','edit','help','run','menu','uninstall')

# Готовые пресеты. Добавить свой — скопируй строку и поменяй значения.
$Presets = @(
  [pscustomobject]@{ Name='tooken';     Title='Tooken Club';                            Url='https://tooken.club';       Model='claude-opus-5-5';                        Free=$false; KeyPage='https://tooken.club' }
  [pscustomobject]@{ Name='openrouter'; Title='OpenRouter (только бесплатные модели)'; Url='https://openrouter.ai/api'; Model='nvidia/nemotron-3-ultra-550b-a55b:free'; Free=$true;  KeyPage='https://openrouter.ai/settings/keys' }
)

function Say($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Fail($t) { Write-Host "  $t" -ForegroundColor Red; exit 1 }
function Ask($t) { $a = Read-Host $t; if ($null -eq $a) { return '' }; return $a.Trim() }
function Yes($t) { $a = (Ask "$t (Y/n)").ToLower(); return ($a -eq '' -or $a -eq 'y' -or $a -eq 'д' -or $a -eq 'да' -or $a -eq 'yes') }
function Mask($k) {
  if (-not $k) { return '(нет)' }
  if ($k.Length -le 10) { return '****' }
  return $k.Substring(0, 4) + '...' + $k.Substring($k.Length - 4)
}
function HostOf($u) { try { return ([uri]$u).Host } catch { return $u } }

# ---------- профили ----------

function ProfPath($n) { Join-Path $Root "$n.json" }

function Read-Prof($n) {
  $p = ProfPath $n
  if (-not (Test-Path $p)) { return $null }
  try { $j = [IO.File]::ReadAllText($p) | ConvertFrom-Json }
  catch { return [pscustomobject]@{ Name = $n; Path = $p; Broken = $true; Url = ''; Key = ''; Model = '(ошибка в файле — cc edit ' + $n + ')'; Small = '' } }
  [pscustomobject]@{
    Name = $n; Path = $p; Broken = $false
    Url = [string]$j.env.ANTHROPIC_BASE_URL; Key = [string]$j.env.ANTHROPIC_AUTH_TOKEN
    Model = [string]$j.env.ANTHROPIC_MODEL; Small = [string]$j.env.ANTHROPIC_DEFAULT_HAIKU_MODEL
    Ctx = [string]$j.env.CLAUDE_CODE_MAX_CONTEXT_TOKENS
  }
}

function Get-Profs {
  if (-not (Test-Path $Root)) { return @() }
  return @(Get-ChildItem $Root -Filter *.json | Sort-Object Name | ForEach-Object { Read-Prof $_.BaseName })
}

function Save-Prof($n, $url, $key, $model, $small, $ctx) {
  if (-not $small) { $small = $model }
  New-Item -ItemType Directory -Force $Root | Out-Null
  New-Item -ItemType Directory -Force $Bin  | Out-Null
  $obj = [ordered]@{
    model = $model
    env   = [ordered]@{
      ANTHROPIC_BASE_URL             = $url
      ANTHROPIC_AUTH_TOKEN           = $key
      ANTHROPIC_API_KEY              = ''        # пусто специально: иначе Claude Code может пойти в Anthropic напрямую
      ANTHROPIC_MODEL                = $model
      ANTHROPIC_DEFAULT_FABLE_MODEL  = $model    # все "семейства" Claude -> выбранная модель (никаких платных подмен)
      ANTHROPIC_DEFAULT_OPUS_MODEL   = $model
      ANTHROPIC_DEFAULT_SONNET_MODEL = $model
      ANTHROPIC_DEFAULT_HAIKU_MODEL  = $small    # мелкие фоновые задачи (заголовки, сжатие)
      CLAUDE_CODE_SUBAGENT_MODEL     = $model
    }
  }
  # размер контекста для "незнакомых" Claude Code моделей (убирает предупреждение и не даёт переполнить окно)
  if ($ctx -and $model -notlike 'claude-*') { $obj.env['CLAUDE_CODE_MAX_CONTEXT_TOKENS'] = [string]$ctx }
  # меню /model внутри Claude Code: показываем модели ЭТОГО сервиса вместо стандартных Opus/Sonnet/Fable
  $ids = @($script:Ids)
  if ($ids.Count -gt 0) {
    if ($ids -notcontains $model) { $ids = @($model) + $ids }
    $rows = @()
    foreach ($id in ($ids | Select-Object -First 40)) {
      $d = 'модель сервиса ' + $n
      if ($id -like '*:free') { $d = 'бесплатная модель OpenRouter' }
      $rows += [ordered]@{ model = $id; label = $id; description = $d }
    }
    $obj['modelPicker'] = [ordered]@{ replaceBuiltInOptions = $true; options = $rows }
  } elseif (Test-Path (ProfPath $n)) {
    # список моделей сейчас не загружали (например, сменили ключ) — оставляем прежнее меню
    try { $old = [IO.File]::ReadAllText((ProfPath $n)) | ConvertFrom-Json; if ($old.modelPicker) { $obj['modelPicker'] = $old.modelPicker } } catch {}
  }
  [IO.File]::WriteAllText((ProfPath $n), ($obj | ConvertTo-Json -Depth 8), $Utf8)
  # команда claude-ИМЯ (работает в PowerShell и cmd без смены политики выполнения)
  $cmd = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File ""%USERPROFILE%\.claude-profiles\cc.ps1"" run $n %*`r`n"
  [IO.File]::WriteAllText((Join-Path $Bin "claude-$n.cmd"), $cmd, (New-Object Text.ASCIIEncoding))
}

function Need-Prof($n) {
  if (-not $n) { Fail 'Укажи имя профиля. Список: cc list' }
  $p = Read-Prof $n.ToLower()
  if (-not $p) { Fail "Профиль '$n' не найден. Список: cc list" }
  return $p
}

# ---------- модели и ключи ----------

$script:Ids = @()
$script:Ctx = @{}

# окно контекста модели: берём из списка моделей, но не больше 200k (больше = дороже и быстрее упираешься в лимиты)
function Ctx-For($model) {
  $c = $script:Ctx[$model]
  if (-not $c) { return '' }
  return [string][math]::Min([int64]$c, 200000)
}

function Get-ModelIds($url, $key, $freeOnly) {
  $script:Ids = @()
  $script:Ctx = @{}
  try {
    # OpenRouter с заголовком anthropic-version отдаёт урезанный список — для него без заголовка
    $h = @{}
    if (-not $freeOnly) { $h['anthropic-version'] = '2023-06-01' }
    if ($key) { $h['Authorization'] = "Bearer $key" }
    $r = Invoke-RestMethod -Uri ($url.TrimEnd('/') + '/v1/models') -Headers $h -TimeoutSec 20
    $items = @($r.data)
    if ($freeOnly) {
      # бесплатные + умеют работать с инструментами (файлы, команды) + контекст от 100k (меньше Claude Code не влезает)
      $items = @($items | Where-Object {
        $_.id -like '*:free' -and
        ($null -eq $_.supported_parameters -or $_.supported_parameters -contains 'tools') -and
        ($null -eq $_.context_length -or [int64]$_.context_length -ge 100000)
      })
    }
    foreach ($it in $items) {
      $c = $it.context_length; if (-not $c) { $c = $it.max_input_tokens }
      if ($it.id -and $c) { $script:Ctx[[string]$it.id] = $c }
    }
    $script:Ids = @($items | ForEach-Object { [string]$_.id } | Where-Object { $_ } | Sort-Object -Unique)
  } catch {}
  return $script:Ids
}

function Pick-Model($url, $key, $default, $freeOnly) {
  Say '  Загружаю список моделей...' DarkGray
  $ids = @(Get-ModelIds $url $key $freeOnly)
  $show = @($ids | Select-Object -First 60)
  if ($ids.Count -gt 0) {
    if ($default -and ($ids -notcontains $default)) { $default = $null }
    if ($freeOnly) { Say '  Бесплатные модели с поддержкой инструментов:' Gray }
    for ($i = 0; $i -lt $show.Count; $i++) {
      $mark = ''; if ($show[$i] -eq $default) { $mark = '   <- рекомендую' }
      Say ('  {0,3}. {1}{2}' -f ($i + 1), $show[$i], $mark)
    }
    if ($ids.Count -gt 60) { Say "  ...и ещё $($ids.Count - 60). Любой ID можно вписать вручную." DarkGray }
  } else {
    Say '  Список моделей не получен — впиши ID модели вручную (он есть на сайте сервиса).' DarkYellow
  }
  $hint = ''; if ($default) { $hint = " [Enter = $default]" }
  while ($true) {
    $a = Ask "  Номер или ID модели$hint"
    if (-not $a -and $default) { return $default }
    if ($a -match '^\d+$' -and $show.Count -gt 0) {
      $n = [int]$a
      if ($n -ge 1 -and $n -le $show.Count) { return $show[$n - 1] }
      Say '  Нет такого номера.' Red; continue
    }
    if ($a) { return $a }
  }
}

# лёгкая модель для фоновых задач: если у сервиса есть haiku того же семейства — берём её
function Pick-Small($model) {
  if ($model -like 'claude-*') {
    $h = @($script:Ids | Where-Object { $_ -like 'claude-haiku*' } | Sort-Object -Descending)
    if ($h.Count -gt 0) { return $h[0] }
  }
  return $model
}

function Read-Key($label) {
  Say '  Вставь ключ (Ctrl+V или правый клик) и нажми Enter. Символы не видны — так и задумано.' DarkGray
  while ($true) {
    $s = Read-Host "  $label" -AsSecureString
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { $k = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
    $k = ([string]$k).Trim().Trim('"').Trim("'")
    if ($k) { Say "  Ключ принят: $(Mask $k)" DarkGray; return $k }
    Say '  Пусто. Попробуй ещё раз.' Red
  }
}

function Norm-Url($u) {
  $u = $u.Trim().TrimEnd('/')
  if ($u -notmatch '^https?://') { $u = 'https://' + $u }
  # Claude Code сам добавляет /v1/messages, поэтому срезаем лишний хвост
  foreach ($tail in @('/v1/messages', '/messages', '/v1')) {
    if ($u.ToLower().EndsWith($tail)) { $u = $u.Substring(0, $u.Length - $tail.Length); Say "  Адрес поправлен: $u (Claude Code сам добавит /v1/messages)" DarkGray; break }
  }
  return $u
}

# ---------- проверка ----------

function Test-Prof($p) {
  Write-Host ('  {0,-14} ' -f $p.Name) -NoNewline
  if ($p.Broken) { Say 'файл профиля повреждён' Red; return $false }
  $body = @{ model = $p.Model; max_tokens = 64; messages = @(@{ role = 'user'; content = 'Reply with one word: ok' }) } | ConvertTo-Json -Depth 5
  $h = @{ 'Authorization' = "Bearer $($p.Key)"; 'anthropic-version' = '2023-06-01' }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  try {
    Invoke-RestMethod -Method Post -Uri ($p.Url.TrimEnd('/') + '/v1/messages') -Headers $h -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 120 | Out-Null
    Say ('работает  ({0} c, {1})' -f [math]::Round($sw.Elapsed.TotalSeconds, 1), $p.Model) Green
    return $true
  } catch {
    $code = $null; $msg = $_.Exception.Message
    if ($_.Exception.Response) { try { $code = [int]$_.Exception.Response.StatusCode } catch {} }
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
    if ($p.Key) { $msg = $msg.Replace($p.Key, (Mask $p.Key)) }
    $msg = ($msg -replace '\s+', ' ')
    if ($msg.Length -gt 220) { $msg = $msg.Substring(0, 220) + '...' }
    $hint = switch ($code) {
      400 { 'запрос отклонён — часто неверный ID модели' }
      401 { 'неверный ключ' }
      402 { 'закончились токены / нужен баланс' }
      403 { 'нет доступа: ключ, баланс или регион' }
      404 { 'не найден адрес API или модель' }
      429 { 'лимит запросов или токены закончились — переключись на другой сервис' }
      default { 'ошибка сети или сервиса' }
    }
    $c = ''; if ($code) { $c = "$code " }
    Say "НЕ работает: $c$hint" Red
    Say "                 $msg" DarkGray
    return $false
  }
}

# ---------- запуск ----------

function Find-Claude {
  $c = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  $exe = Join-Path $Bin 'claude.exe'
  if (Test-Path $exe) { return $exe }
  Fail 'Claude Code не найден. Установи: irm https://claude.ai/install.ps1 | iex   (потом перезапусти терминал)'
}

$UserSettings = Join-Path $env:USERPROFILE '.claude\settings.json'

# снимок поля "model" в общем settings.json: @{ Exists = есть ли файл; Has = есть ли поле; Value = значение }
function Get-UserModel {
  $s = @{ Exists = (Test-Path $UserSettings); Has = $false; Value = $null }
  if ($s.Exists) {
    try {
      $j = [IO.File]::ReadAllText($UserSettings) | ConvertFrom-Json
      if ($j.PSObject.Properties.Name -contains 'model') { $s.Has = $true; $s.Value = $j.model }
    } catch { $s.Exists = $false }   # не смогли прочитать — тогда и трогать не будем
  }
  return $s
}

function Restore-UserModel($before) {
  try {
    if (-not (Test-Path $UserSettings)) { return }
    $now = Get-UserModel
    if ($now.Has -eq $before.Has -and $now.Value -eq $before.Value) { return }   # ничего не поменялось
    $j = [IO.File]::ReadAllText($UserSettings) | ConvertFrom-Json
    if ($before.Has) { $j.model = $before.Value }
    else { $j.PSObject.Properties.Remove('model') }
    [IO.File]::WriteAllText($UserSettings, ($j | ConvertTo-Json -Depth 64), $Utf8)
  } catch {}
}

function Start-Prof($n, $rest) {
  $p = Need-Prof $n
  if ($p.Broken) { Fail "Профиль $($p.Name) повреждён. Исправь: cc edit $($p.Name)" }
  $exe = Find-Claude
  [IO.File]::WriteAllText($LastFile, $p.Name, $Utf8)
  Say ''
  Say "  >> Claude Code через $($p.Name) ($(HostOf $p.Url)): $($p.Model)" Cyan
  Say "     выйти: /exit    сменить сервис: cc    продолжить этот диалог в другом: cc ИМЯ -c" DarkGray
  Say ''
  if ($null -eq $rest) { $rest = @() }
  # Ключ и адрес кладём в переменные окружения процесса (так Claude Code видит авторизацию сразу при старте),
  # а --settings дополнительно перекрывает общий settings.json, если там прописан другой сервис.
  $j = [IO.File]::ReadAllText($p.Path) | ConvertFrom-Json
  foreach ($prop in $j.env.PSObject.Properties) { Set-Item -Path ("Env:" + $prop.Name) -Value ([string]$prop.Value) }
  # выбор в /model Claude Code сохраняет в общий settings.json — после выхода возвращаем как было,
  # чтобы модель одного сервиса не "протекла" в обычный claude и другие профили
  $before = Get-UserModel
  & $exe --settings $p.Path @rest
  $code = $LASTEXITCODE
  Restore-UserModel $before
  exit $code
}

# ---------- команды ----------

function List-Profs {
  $ps = Get-Profs
  if ($ps.Count -eq 0) { Say '  Профилей нет. Добавь: cc add' Yellow; return }
  $last = ''; if (Test-Path $LastFile) { $last = ([IO.File]::ReadAllText($LastFile)).Trim() }
  Say ''
  for ($i = 0; $i -lt $ps.Count; $i++) {
    $p = $ps[$i]; $mark = ''; if ($p.Name -eq $last) { $mark = '  <- последний' }
    Say ('  {0,2}. {1,-14} {2,-40} {3}{4}' -f ($i + 1), $p.Name, $p.Model, (HostOf $p.Url), $mark)
  }
  Say ''
}

function Show-Menu {
  $ps = Get-Profs
  Say ''
  Say '  Claude Code — выбери сервис' Cyan
  if ($ps.Count -eq 0) { Say ''; Say '  Профилей пока нет — добавим первый.' Yellow; Add-Prof; return }
  List-Profs
  Say '  Номер — запустить.  Номер + c (например 2c) — продолжить прошлый диалог.' DarkGray
  Say '  a — добавить сервис   t — проверить все   q — выход' DarkGray
  $last = ''; if (Test-Path $LastFile) { $last = ([IO.File]::ReadAllText($LastFile)).Trim() }
  $hint = ''; if ($last -and (Read-Prof $last)) { $hint = " [Enter = $last]" } else { $last = '' }
  $a = (Ask "  Выбор$hint").ToLower()
  if ($a -eq '' -and $last) { Start-Prof $last @() }
  if ($a -eq 'q' -or $a -eq '') { return }
  if ($a -eq 'a') { Add-Prof; return }
  if ($a -eq 't') { Test-All; return }
  if ($a -match '^(\d+)\s*c$') { $n = [int]$Matches[1]; if ($n -ge 1 -and $n -le $ps.Count) { Start-Prof ($ps[$n - 1].Name) @('--continue') } }
  if ($a -match '^\d+$') { $n = [int]$a; if ($n -ge 1 -and $n -le $ps.Count) { Start-Prof ($ps[$n - 1].Name) @() } }
  if (Read-Prof $a) { Start-Prof $a @() }
  Say '  Не понял выбор.' Red
}

function Test-All($only) {
  $ps = Get-Profs
  if ($only) { $ps = @(Need-Prof $only) }
  if ($ps.Count -eq 0) { Say '  Профилей нет. Добавь: cc add' Yellow; return }
  Say ''; Say '  Проверяю (короткий запрос к каждому сервису)...' DarkGray
  foreach ($p in $ps) { Test-Prof $p | Out-Null }
  Say ''
}

function Add-Prof {
  Say ''
  Say '  Какой сервис добавить?' Cyan
  for ($i = 0; $i -lt $Presets.Count; $i++) { Say ('  {0}. {1}' -f ($i + 1), $Presets[$i].Title) }
  Say ('  {0}. Другой сервис (свой адрес API)' -f ($Presets.Count + 1))
  $c = Ask '  Номер'
  $free = $false; $default = ''
  if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $Presets.Count) {
    $pr = $Presets[[int]$c - 1]
    $name = $pr.Name; $url = $pr.Url; $default = $pr.Model; $free = $pr.Free
    Say "  Ключ берётся тут: $($pr.KeyPage)" DarkGray
  } else {
    Say '  Нужны 3 вещи с сайта сервиса: адрес API (base URL), ключ и название модели.' DarkGray
    Say '  Сервис должен поддерживать формат Anthropic (в инструкции к Claude Code он обычно указан как ANTHROPIC_BASE_URL).' DarkGray
    $name = ''
    $url = ''
    while (-not $url) { $url = Ask '  Адрес API, например https://example.com' }
    $url = Norm-Url $url
  }
  while ($true) {
    if (-not $name) { $name = (Ask '  Короткое имя латиницей (будет команда claude-ИМЯ)').ToLower() }
    if ($name -notmatch '^[a-z0-9][a-z0-9-]{0,30}$') { Say '  Только латиница, цифры и дефис, например: mysvc' Red; $name = ''; continue }
    if ($Reserved -contains $name) { Say '  Это имя занято командой cc, выбери другое.' Red; $name = ''; continue }
    if (Read-Prof $name) {
      $alt = (Ask "  Профиль '$name' уже есть. Новое имя (например ${name}2) или Enter — перезаписать").ToLower()
      if ($alt) { $name = $alt; continue }
    }
    break
  }
  $key = Read-Key "API-ключ для $name"
  $model = Pick-Model $url $key $default $free
  $small = Pick-Small $model
  Save-Prof $name $url $key $model $small (Ctx-For $model)
  Say ''
  Say "  Сохранено: $(ProfPath $name)" DarkGray
  $ok = Test-Prof (Read-Prof $name)
  Say ''
  if ($ok) { Say "  Готово! Запуск:  cc $name   или   claude-$name" Green }
  else     { Say "  Профиль сохранён, но проверка не прошла. Сменить ключ: cc key $name   модель: cc model $name" Yellow }
  Say ''
  if (Yes '  Запустить Claude Code сейчас?') { Start-Prof $name @() }
}

function Set-Key($n) {
  $p = Need-Prof $n
  $k = Read-Key "Новый ключ для $($p.Name)"
  Save-Prof $p.Name $p.Url $k $p.Model $p.Small $p.Ctx
  Test-Prof (Read-Prof $p.Name) | Out-Null
}

function Set-Model($n, $m) {
  $p = Need-Prof $n
  $free = ($p.Url -like '*openrouter.ai*')
  if (-not $m) { $m = Pick-Model $p.Url $p.Key $p.Model $free }
  else { Get-ModelIds $p.Url $p.Key $free | Out-Null }
  $small = $p.Small; if ($p.Small -eq $p.Model) { $small = $m }
  Save-Prof $p.Name $p.Url $p.Key $m $small (Ctx-For $m)
  Say "  Модель $($p.Name): $m" Green
  Test-Prof (Read-Prof $p.Name) | Out-Null
}

function Remove-Prof($n) {
  $p = Need-Prof $n
  if (-not (Yes "  Удалить профиль $($p.Name)?")) { return }
  Remove-Item $p.Path -Force
  $cmd = Join-Path $Bin "claude-$($p.Name).cmd"
  if (Test-Path $cmd) { Remove-Item $cmd -Force }
  Say '  Удалено.' Green
}

# Сносит всё, что поставил cc (команды, профили, ключи). Сам Claude Code не трогает.
function Uninstall-All {
  Say ''
  Say '  Будет удалено: команда cc, команды claude-ИМЯ, все профили и сохранённые ключи.' Yellow
  Say '  Сам Claude Code останется.' DarkGray
  $a = (Ask '  Точно удалить? (y/N)').ToLower()
  if (@('y', 'yes', 'д', 'да') -notcontains $a) { Say '  Отменено.' DarkGray; return }
  foreach ($p in (Get-Profs)) {
    $c = Join-Path $Bin "claude-$($p.Name).cmd"
    if (Test-Path $c) { Remove-Item $c -Force }
  }
  if (Test-Path $Root) { Remove-Item $Root -Recurse -Force }
  # cc.cmd сейчас выполняется — удаляем его через пару секунд отдельным процессом
  $ccCmd = Join-Path $Bin 'cc.cmd'
  if (Test-Path $ccCmd) {
    Start-Process cmd.exe -ArgumentList "/c timeout /t 2 /nobreak >nul & del /f /q `"$ccCmd`"" -WindowStyle Hidden
  }
  Say '  Готово, всё удалено. Установить заново — снова запусти cc-install.ps1 той же командой, что в первый раз.' Green
}

function Show-Help {
  Say ''
  Say '  cc                 меню: выбрать сервис и запустить Claude Code' Gray
  Say '  cc ИМЯ             запустить профиль (то же, что claude-ИМЯ)' Gray
  Say '  cc ИМЯ -c          продолжить прошлый диалог через этот сервис' Gray
  Say '  cc add             добавить сервис' Gray
  Say '  cc list            список профилей' Gray
  Say '  cc test [ИМЯ]      проверить ключи и модели' Gray
  Say '  cc model ИМЯ       сменить модель' Gray
  Say '  cc key ИМЯ         сменить ключ' Gray
  Say '  cc edit ИМЯ        открыть файл профиля' Gray
  Say '  cc rm ИМЯ          удалить профиль' Gray
  Say '  cc uninstall       удалить cc и все профили (Claude Code останется)' Gray
  Say ''
  Say "  Профили лежат в $Root" DarkGray
  Say ''
}

# ---------- разбор команды ----------

if ($env:CC_NO_MAIN -eq '1') { return }   # для тестов: только загрузить функции

$Argv = @($args)
$cmd = ''; $rest = @()
if ($Argv.Count -gt 0) { $cmd = ([string]$Argv[0]).ToLower() }
if ($Argv.Count -gt 1) { $rest = @($Argv[1..($Argv.Count - 1)]) }
$arg1 = ''; if ($rest.Count -gt 0) { $arg1 = [string]$rest[0] }

switch ($cmd) {
  ''        { Show-Menu; break }
  'menu'    { Show-Menu; break }
  'add'     { Add-Prof; break }
  'list'    { List-Profs; break }
  'ls'      { List-Profs; break }
  'test'    { Test-All $arg1; break }
  'key'     { Set-Key $arg1; break }
  'model'   { $m = ''; if ($rest.Count -gt 1) { $m = [string]$rest[1] }; Set-Model $arg1 $m; break }
  'edit'    { $p = Need-Prof $arg1; Start-Process notepad.exe -ArgumentList "`"$($p.Path)`""; break }
  'rm'      { Remove-Prof $arg1; break }
  'remove'  { Remove-Prof $arg1; break }
  'del'     { Remove-Prof $arg1; break }
  'help'    { Show-Help; break }
  'uninstall' { Uninstall-All; break }
  '-h'      { Show-Help; break }
  '--help'  { Show-Help; break }
  'run'     { Start-Prof $arg1 @($rest | Select-Object -Skip 1); break }
  default   { Start-Prof $cmd $rest }
}
'@
  [IO.File]::WriteAllText((Join-Path $Root 'cc.ps1'), $ccSource, (New-Object System.Text.UTF8Encoding $true))
  $cmd = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File ""%USERPROFILE%\.claude-profiles\cc.ps1"" %*`r`n"
  [IO.File]::WriteAllText((Join-Path $Bin 'cc.cmd'), $cmd, (New-Object System.Text.ASCIIEncoding))

  # папка .local\bin в PATH (обычно её уже добавил установщик Claude Code)
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (-not $userPath) { $userPath = '' }
  if ($env:CC_SKIP_PATH -ne '1' -and ($userPath -split ';') -notcontains $Bin) {
    $newPath = (($userPath.TrimEnd(';')) + ';' + $Bin).TrimStart(';')
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
  }
  if (($env:Path -split ';') -notcontains $Bin) { $env:Path = $env:Path.TrimEnd(';') + ';' + $Bin }
  Say '  [2/3] Команда cc установлена' Green

  # 3. Пропустить экран входа в аккаунт Anthropic при первом запуске
  $cj = Join-Path $env:USERPROFILE '.claude.json'
  if (-not (Test-Path $cj)) {
    [IO.File]::WriteAllText($cj, '{"hasCompletedOnboarding": true}', (New-Object System.Text.UTF8Encoding $false))
  } else {
    $t = [IO.File]::ReadAllText($cj)
    $t2 = $t
    if ($t -match '"hasCompletedOnboarding"\s*:\s*false') {
      $t2 = $t -replace '"hasCompletedOnboarding"\s*:\s*false', '"hasCompletedOnboarding": true'
    } elseif ($t -notmatch '"hasCompletedOnboarding"') {
      if ($t -match '^\s*\{\s*\}\s*$' -or $t.Trim() -eq '') { $t2 = '{"hasCompletedOnboarding": true}' }
      else { $t2 = ([regex]'^\s*\{').Replace($t, '{"hasCompletedOnboarding": true,', 1) }
    }
    if ($t2 -ne $t) {
      Copy-Item $cj "$cj.backup-cc" -Force
      [IO.File]::WriteAllText($cj, $t2, (New-Object System.Text.UTF8Encoding $false))
    }
  }
  Say '  [3/3] Первый запуск без входа в аккаунт Anthropic' Green

  Say ''
  Say '  Готово! Команды:' Cyan
  Say '    cc          меню: выбрать сервис и запустить Claude Code'
  Say '    cc add      добавить сервис (Tooken, OpenRouter или любой свой)'
  Say '    cc test     проверить, где ещё есть токены'
  Say '    cc help     все команды'
  Say ''

  $a = Read-Host '  Добавить первый сервис прямо сейчас? (Y/n)'
  if ($null -eq $a) { $a = 'n' }
  if ($a.Trim() -eq '' -or $a.Trim().ToLower() -in @('y', 'yes', 'д', 'да')) {
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'cc.ps1') add
  } else {
    Say '  Когда будешь готов — набери: cc add' DarkGray
  }
}
