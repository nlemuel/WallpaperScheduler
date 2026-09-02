# Wallpaper Scheduler — arquitetura de produção

## Decisão de arquitetura

A solução recomendada combina três camadas, todas apontando para o mesmo script
idempotente `Set-Wallpaper.ps1`:

1. gatilho no logon do usuário;
2. gatilhos semanais em todas as mudanças de período, inclusive 00:00;
3. watchdog opcional a cada 30 minutos (`-EnableWatchdog`), com janela renovável
   de dez anos.

O script nunca recebe o nome da imagem do gatilho. Ele consulta a data e a hora
reais, escolhe o período vigente em `config.json` e aplica a imagem. Assim, um
gatilho executado com atraso não restaura um wallpaper que já venceu.

Wallpaper é estado de perfil e de sessão interativa (`HKCU` + `user32.dll`). Por
isso, a tarefa deve executar como o próprio usuário, com `LogonType Interactive`.
Não use SYSTEM e não marque “Executar independentemente de o usuário estar
conectado”: uma tarefa na sessão 0 pode até alterar outro registro, mas não é uma
forma confiável de atualizar a área de trabalho visível.

## Horários extraídos do SVG

| Dias | Períodos considerados | Gatilhos de transição |
|---|---|---|
| Domingo e sábado | 00:00–07:59 madrugada; 08:00–16:29 manhã; 16:30–23:59 noite | 00:00, 08:00, 16:30 |
| Segunda | antes de 10:00; dia a partir de 10:00 | 00:00, 10:00 |
| Terça, quinta e sexta | 00:00–06:59 madrugada; 07:00–17:59 dia; 18:00–23:59 noite | 00:00, 07:00, 18:00 |
| Quarta | antes de 19:00; noite a partir de 19:00 | 00:00, 19:00 |

O SVG é internamente inconsistente: sua caixa de tarefas ainda lista domingo
07:00/17:00, quarta 18:00 e sexta 04:10, enquanto os blocos de decisão mostram os
limites acima. Esta implementação considera os blocos de períodos como a versão
vigente. Se 04:10 for realmente o início de um wallpaper diferente na sexta,
adicione uma entrada às 04:10 em `config.json` e um gatilho equivalente no
instalador.

O desenho também não identifica qual imagem vale na segunda antes de 10:00 nem
na quarta antes de 19:00. O exemplo usa nomes explícitos
`segunda-antes-10h.jpg` e `quarta-antes-19h.jpg`, evitando preencher a lacuna de
forma silenciosa. Substitua os arquivos ou os nomes no JSON pela regra de negócio
correta.

## Estrutura

```text
C:\ProgramData\WallpaperScheduler\
├── config.json
├── Set-Wallpaper.ps1
├── Run-Wallpaper.bat
└── images\
    ├── domingo-madrugada.jpg
    ├── domingo-manha.jpg
    ├── domingo-noite.jpg
    └── ...demais nomes declarados em config.json

%LOCALAPPDATA%\WallpaperScheduler\Logs\
├── wallpaper.log
└── wallpaper.log.old
```

Scripts e imagens ficam em `ProgramData` para terem caminho estável; logs ficam
no perfil do usuário para não exigir elevação. Conceda aos usuários somente
leitura na pasta instalada. Alterações no conteúdo devem ficar restritas a
administradores.

## Instalação

1. Coloque as imagens em uma subpasta `images` ao lado destes arquivos, com os
   nomes de `config.json`.
2. Abra o Windows PowerShell 5.1 como administrador, usando a conta que receberá
   a tarefa.
3. Execute:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& '.\Register-WallpaperTask.ps1'
```

Para habilitar a reconciliação adicional a cada 30 minutos:

```powershell
& '.\Register-WallpaperTask.ps1' -EnableWatchdog
```

O instalador copia o pacote, registra `WallpaperScheduler-<usuario>` e inicia a
tarefa uma vez. Repita em cada conta local. Em domínio, distribua os arquivos por
GPO/Intune e registre a tarefa no contexto de cada usuário. Uma única tarefa como
SYSTEM não substitui tarefas por usuário, especialmente com troca rápida de
usuário ou sessões RDP simultâneas.

## Configuração equivalente no Agendador de Tarefas

O script de registro cria uma tarefa com:

- **Programa:**
  `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`
- **Argumentos:**
  `-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\ProgramData\WallpaperScheduler\Set-Wallpaper.ps1"`
- **Iniciar em:** `C:\ProgramData\WallpaperScheduler`
- **Conta:** usuário atual;
- **Tipo de logon:** interativo;
- **Privilégio:** limitado; não precisa de “Executar com privilégios mais altos”;
- **Gatilhos:** logon + todos os horários da tabela;
- **Executar assim que possível após um início perdido:** habilitado;
- **Bateria:** permitir iniciar e não interromper;
- **Falha:** três reinícios, intervalo de um minuto;
- **Instâncias simultâneas:** ignorar nova instância;
- **Limite:** cinco minutos.

É possível criar tarefas separadas para cada horário, porém uma tarefa com vários
gatilhos reduz configuração duplicada e risco de divergência. O histórico ainda
mostra cada execução individualmente.

## O que acontece nos cenários críticos

### Computador desligado no horário

Nada executa enquanto ele está desligado. Ao iniciar, `StartWhenAvailable`
mantém o disparo perdido elegível. Como a tarefa exige token interativo, a ação
poderá rodar quando a conta estiver conectada. O gatilho de logon normalmente a
corrige antes e de forma direta. Não se deve prometer troca antes do logon: não há
desktop daquele usuário para atualizar.

O Agendador não precisa reproduzir cada troca perdida. Uma única execução calcula
o estado atual. Essa propriedade é essencial; uma tarefa que recebesse
“aplique domingo-manhã” poderia rodar atrasada à noite e causar erro.

### Sessão bloqueada, suspensão e hibernação

Se o usuário continua conectado, a tarefa interativa pode executar com a sessão
bloqueada; não é preciso deixar a tela desbloqueada. Em suspensão ou hibernação,
ela não roda durante o sono. Ao retomar, a opção de início perdido permite a
execução. “Acordar o computador para executar” é opcional e não foi habilitado,
pois consome energia; pode ser ativado se a política exigir.

### Inicialização sem login

Ainda não existe área de trabalho interativa a ser alterada. Após o login, o
gatilho de logon aplica a imagem correta. Apenas chegar à tela de credenciais não
é login.

### Troca rápida de usuário e RDP

Cada conta precisa de sua própria tarefa e configuração. A tarefa de um usuário
não deve escrever no `HKCU` de outro. Em múltiplas sessões, cada tarefa atualiza a
sessão à qual pertence.

## A tarefa de logon é suficiente?

Ela é suficiente para corrigir o estado depois de uma máquina desligada, desde
que haja login. Sozinha, porém, não troca o wallpaper enquanto a pessoa permanece
conectada atravessando um limite de horário. Somente tarefas por horário também
não são ideais: podem ficar indisponíveis, desabilitadas, perder o token
interativo ou sofrer atraso. A combinação é a opção mais confiável.

## Testes e diagnóstico

Teste a seleção sem alterar o desktop:

```powershell
& 'C:\ProgramData\WallpaperScheduler\Set-Wallpaper.ps1' -At '2026-09-06 08:00' -DryRun
& 'C:\ProgramData\WallpaperScheduler\Set-Wallpaper.ps1' -At '2026-09-09 19:00' -DryRun
```

Consulte estado e resultado:

```powershell
Get-ScheduledTask -TaskName "WallpaperScheduler-$env:USERNAME" |
    Get-ScheduledTaskInfo
Get-Content "$env:LOCALAPPDATA\WallpaperScheduler\Logs\wallpaper.log" -Tail 50
```

No Agendador, habilite o histórico operacional quando precisar investigar. Códigos
comuns: `0x0` é sucesso; `0x1` indica erro do script; `0x41301` significa que a
tarefa ainda está em execução.

## Falhas e mitigação

| Falha | Mitigação aplicada/recomendada |
|---|---|
| Imagem ausente ou nome incorreto | validação explícita, retorno 1 e log com caminho completo |
| Horários com minutos comparados incorretamente | conversão para minutos totais; 16:30 = 990 |
| Tarefa atrasada aplica imagem vencida | toda execução recalcula dia e hora atuais |
| Virada do dia mantém imagem anterior | gatilho 00:00 em todos os dias |
| Computador desligado | `StartWhenAvailable` + correção no logon |
| Suspensão atravessa transição | início perdido; watchdog opcional |
| Concorrência entre logon e horário | política `IgnoreNew`; operação idempotente |
| Falha transitória | três tentativas com intervalo de um minuto |
| Política corporativa sobrescreve wallpaper | alinhar GPO/MDM; esse script não pode vencer uma política imposta de forma confiável |
| Windows Spotlight/tema sincronizado muda a imagem | desabilitar o mecanismo concorrente ou aceitar que o watchdog a reconcilie |
| Arquivo em rede indisponível | manter cópia local em `ProgramData` |
| Horário/fuso incorreto | sincronizar Windows Time e validar o fuso do equipamento |
| Alteração de horário de verão | gatilhos usam hora local; testar transições de DST quando aplicável |
| Antivírus/AppLocker bloqueia script | assinar o script e liberar publisher/caminho; preferir `AllSigned` em produção |

## Recomendação final

Em ambiente real eu usaria uma tarefa por usuário, contendo logon e todos os
gatilhos exatos, com o watchdog de 30 minutos habilitado quando o custo de uma
imagem incorreta for maior que o custo de execuções leves. Manteria configuração,
script assinado e imagens versionadas localmente em `ProgramData`, distribuiria
por GPO/Intune e monitoraria código de saída e log. O BAT ficaria apenas como
atalho de suporte/compatibilidade; a tarefa chamaria PowerShell diretamente para
preservar diagnóstico e reduzir uma camada desnecessária.
