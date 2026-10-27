#!/usr/bin/env bash
# =============================================================================
#  simul.sh — Simulação de 3 meses (92 dias) da chain '#alertas-rio-madeira'
#  utilizando Freechains v0.20 (https://github.com/Freechains/freechains.vcs/blob/v0.20/cli.md)
#
#  Aplicação final (Pergunta #5):
#    Sistema Comunitário de Alerta e Resposta a Emergências (alerta.py / web)
#    Repositório da aplicação: https://github.com/Paulino0416/Aplica-o-Freechains
#
#  Convenção de tags no payload e regras da aplicação (camada de UI sobre o protocolo):
#    - Tags de postagens:
#        [ALERTA] <texto>                -> emite alerta de emergência
#        [CONFIRMA <id12>] <texto>       -> confirma alerta presencialmente
#        [PROTOCOLO <id12>] <texto>      -> protocolo de resposta (rotas/abrigos da memória)
#        [COORD <id12>] <texto>          -> coordenação de campo (barcos, vagas, resgate)
#        [ENCERRA <id12>] <texto>        -> encerra emergência e abre fase de avaliação
#        [INFO] <texto>                  -> informação de rotina (vira memória após 24h)
#        [COLETA] <texto>                -> coleta diária de reps (+1.000 após 24h, condicionada
#                                           a ter emitido alerta válido ou ajudado nas últimas 24h)
#
#    - Limiares e papéis na aplicação (calculados lendo `reps author`):
#        * membro       (< 10.000 reps)  : alertas nascem PENDENTE
#        * CONFIRMADOR  (>= 10.000 reps) : confirmações contam p/ promover alerta a CONFIRMADO (2+)
#        * Alerta ATIVO (>= 15.000 reps) : alerta de autor muito confiável já nasce ATIVO
#        * COORDENADOR  (>= 19.000 reps) : publica [PROTOCOLO] e [ENCERRA] emergências
#
#  Topologia (3 nós P2P independentes, sincronizados em malha com --now=<secs>):
#    - Nó 1 (N1, porta 8401 - Sede da Defesa Civil)     : defesa, fernando
#    - Nó 2 (N2, porta 8402 - Bairro Rua Amazonas)      : eva, gisele, henrique
#    - Nó 3 (N3, porta 8403 - Comunidade Ribeirinha)    : marcos, joao, igor, lucia
#
#  Requisitos: git, openssh-client, lua5.4, freechains v0.20
#  Execução:   bash simul.sh | tee simul.log
# =============================================================================

set -uo pipefail     # sem -e: falhas esperadas (ex.: post sem reps ou get de revogado) não abortam

FREECHAINS=${FREECHAINS:-freechains}

# --- Funções auxiliares (wrappers sobre a CLI do Freechains v0.20) ------------
# FC  : imprime e executa o comando `freechains`
# FCH : idem, salvando o hash da ação criada na variável global $HASH
FC () {
    echo "\$ freechains $*"
    "$FREECHAINS" "$@" || echo "   !! (falhou — verificar se era esperado)"
}
FCH () {
    local out
    echo "\$ freechains $*"
    if out=$("$FREECHAINS" "$@"); then
        echo "$out"
        HASH=${out##*$'\n'}
    else
        echo "   !! (falhou — verificar se era esperado)"
        HASH=""
    fi
}
id12 () { echo "${1:0:12}"; }   # prefixo de 12 caracteres usado nas tags [CONFIRMA/PROTOCOLO/COORD/ENCERRA]
titulo () { echo; echo "################ $* ################"; echo; }

# --- Diretórios dos 3 nós e portas dos daemons -------------------------------
BASE=/tmp/simul-alertas
KEYS=$BASE/keys
N1=$BASE/N1      # Nó 1: Sede da Defesa Civil (centro)
N2=$BASE/N2      # Nó 2: Bairro Rua Amazonas (escola/abrigo)
N3=$BASE/N3      # Nó 3: Comunidade ribeirinha (porto/barqueiros)
P1=8401; P2=8402; P3=8403
C='#alertas-rio-madeira'

# Limpa eventuais daemons e dados de execuções anteriores
pkill -f "base-path=$BASE" 2>/dev/null || true
sleep 1
rm -rf "$BASE"
mkdir -p "$N1" "$N2" "$N3" "$KEYS"

# --- Controle de passagem de tempo (--now=<secs>) ----------------------------
T0=1790000000          # Dia 0 da simulação (epoch em segundos)
DAY=86400              # 1 dia  = 86.400 s
HOUR=3600              # 1 hora =  3.600 s
# D <dia> [segundos_extras] -> retorna timestamp absoluto para --now=<secs>
D () { echo $(( T0 + $1*DAY + ${2:-0} )); }

# --- Geração das chaves ed25519 dos 9 usuários -------------------------------
#  defesa   : pioneira institucional (Defesa Civil)             -> N1
#  fernando : enfermeiro voluntário muito ativo (COORDENADOR)   -> N1
#  eva      : líder de rua atenta, emite alertas reais          -> N2
#  gisele   : diretora da escola/abrigo (CONFIRMADOR)           -> N2
#  henrique : newbie, entra sem reps usando --beg               -> N2
#  marcos   : barqueiro, posta rotas e alertas úteis ("viral")  -> N3
#  joao     : troll / sabotador, posta alarmes falsos e boatos  -> N3
#  igor     : precipitado / pouco confiável, depois se redime   -> N3
#  lucia    : moradora passiva (lurker), apenas lê e vota       -> N3
for u in defesa fernando eva gisele henrique marcos joao igor lucia; do
    ssh-keygen -t ed25519 -C '' -N '' -q -f "$KEYS/$u"
done
k  () { echo "$KEYS/$1"; }          # caminho da chave privada
kp () { echo "$KEYS/$1.pub"; }      # caminho da chave pública

# Define em qual nó (--root) cada usuário opera
root_of () {
    case $1 in
        defesa|fernando)        echo "$N1" ;;
        eva|gisele|henrique)    echo "$N2" ;;
        *)                      echo "$N3" ;;
    esac
}

# --- Atalhos para ações na chain ---------------------------------------------
post ()     { FCH --root="$(root_of "$1")" --now="$2" chain "$C" post inline "$3" --sign="$(k "$1")"; }
beg ()      { FCH --root="$(root_of "$1")" --now="$2" chain "$C" post inline "$3" --beg --sign="$(k "$1")"; }
like ()     { FC  --root="$(root_of "$1")" --now="$2" chain "$C" like    "$3" "$4" "$5" --sign="$(k "$1")" ${6:+--why="$6"} ${7:+"$7"}; }
dislike ()  { FC  --root="$(root_of "$1")" --now="$2" chain "$C" dislike "$3" "$4" "$5" --sign="$(k "$1")" ${6:+--why="$6"}; }
revoke ()   { FC  --root="$(root_of "$1")" --now="$2" chain "$C" revoke   "$3" "$4" --sign="$(k "$1")" ${5:+--why="$5"}; }
unrevoke () { FC  --root="$(root_of "$1")" --now="$2" chain "$C" unrevoke "$3" "$4" --sign="$(k "$1")" ${5:+"$5"} ${6:+--why="$6"}; }

# Sincronização P2P em malha entre N1, N2 e N3 (evita hard forks de 7 dias / 100 ações)
sync_all () {
    local t=$1
    for _ in 1 2; do
        FC --root="$N1" --now="$t" chain "$C" sync recv localhost:$P2
        FC --root="$N1" --now="$t" chain "$C" sync recv localhost:$P3
        FC --root="$N2" --now="$t" chain "$C" sync recv localhost:$P1
        FC --root="$N2" --now="$t" chain "$C" sync recv localhost:$P3
        FC --root="$N3" --now="$t" chain "$C" sync recv localhost:$P1
        FC --root="$N3" --now="$t" chain "$C" sync recv localhost:$P2
    done
}

# Exibe o placar de reputação e o papel de cada usuário na aplicação
placar () {
    echo "---- Placar de Reputação e Papéis na Aplicação em $(date -u -d "@$1" +%F 2>/dev/null || echo "$1") ----"
    FC --root="$N1" --now="$1" chain "$C" reps authors
    for u in defesa fernando eva gisele henrique marcos joao igor lucia; do
        local r papel
        r=$("$FREECHAINS" --root="$N1" --now="$1" chain "$C" reps author "$(kp "$u")" 2>/dev/null || echo 0)
        if   [ "${r:-0}" -ge 19000 ] 2>/dev/null; then papel="COORDENADOR (>=19k)"
        elif [ "${r:-0}" -ge 15000 ] 2>/dev/null; then papel="CONFIRMADOR / Alerta ATIVO (>=15k)"
        elif [ "${r:-0}" -ge 10000 ] 2>/dev/null; then papel="CONFIRMADOR (>=10k)"
        else                                           papel="membro (<10k)"
        fi
        printf '  %-9s : %6s reps  [%s]\n' "$u" "$r" "$papel"
    done
}

# Consulta payload (para comprovar revogação ou restauração via unrevoke)
ver () { FC --root="$N1" chain "$C" get payload "$1"; }

# =============================================================================
titulo "SEMANA 0 (Dia 0) — Criação da chain, daemons P2P e bloqueio anti-Sybil"
# =============================================================================
# Nó 1 inicializa a chain tendo `defesa` como pioneira (recebe 30.000 reps iniciais)
FC --root="$N1" --now="$(D 0)" chains add "$C" init --pioneer="$(kp defesa)"
FC --root="$N1" daemon start --port=$P1 -- --listen=127.0.0.1 --reuseaddr &
sleep 1

# Nós 2 e 3 entram clonando a chain do Nó 1 e iniciam seus próprios daemons
FC --root="$N2" chains add "$C" clone localhost:$P1
FC --root="$N3" chains add "$C" clone localhost:$P1
FC --root="$N2" daemon start --port=$P2 -- --listen=127.0.0.1 --reuseaddr &
FC --root="$N3" daemon start --port=$P3 -- --listen=127.0.0.1 --reuseaddr &
sleep 1

# Defesa Civil publica as regras e a convenção da aplicação usando [INFO]
post defesa "$(D 0 600)" $'[INFO] Regras da chain #alertas-rio-madeira: use [ALERTA], [CONFIRMA], [PROTOCOLO], [COORD], [ENCERRA], [INFO] e [COLETA]. Boatos serao revogados.\n'
REGRAS=$HASH

# Teste anti-Sybil: João (no N3, ainda com 0 reps) tenta publicar sem usar --beg e falha
echo "-- esperado: falha por falta de reputação (joao tem 0 reps)"
post joao "$(D 0 900)" $'[INFO] Oi gente, testando post sem reputacao.\n'

sync_all "$(D 0 1200)"

# =============================================================================
titulo "SEMANAS 1-2 (Dias 1 a 14) — Semeadura de papéis e Memória Institucional ([INFO])"
# =============================================================================
# No Dia 1 (24h após o post inicial), `defesa` consolidou +1.000 reps (total: 31.000).
# Ela faz uma postagem de rotina para ganhar mais +1.000 no Dia 2 (chegando a 32.000)
# e distribui reputação para estruturar os papéis da aplicação:
post defesa "$(D 1 60)" $'[INFO] Monitoramento hidrologico da Defesa Civil ativo na ponte.\n'
sync_all "$(D 1 120)"

# Dia 2: Defesa Civil distribui likes diretos aos autores conhecidos da comunidade:
# - Fernando recebe 22.000 (19.800 líquidos após taxa de 10%) -> torna-se COORDENADOR (>= 19.000)!
# - Gisele recebe 12.000 (10.800 líquidos) -> torna-se CONFIRMADOR (>= 10.000)!
like defesa "$(D 2 100)" 22000 author "$(kp fernando)" "enfermeiro voluntario e coordenador"
like defesa "$(D 2 200)" 12000 author "$(kp gisele)"   "diretora da Escola Municipal (abrigo)"
sync_all "$(D 2 400)"

# Fernando e Gisele acolhem os demais moradores nos nós N2 e N3 (rede não-permissionada):
like fernando "$(D 3 100)" 4000 author "$(kp eva)"    "lider comunitaria na Rua Amazonas"
like fernando "$(D 3 200)" 4000 author "$(kp marcos)" "barqueiro experiente do porto"
like gisele   "$(D 3 300)" 2000 author "$(kp joao)"   "morador ribeirinho"
like gisele   "$(D 3 400)" 2500 author "$(kp igor)"   "disse que possui kit de socorro"
sync_all "$(D 3 450)"
like eva      "$(D 3 500)" 1500 author "$(kp lucia)"  "vizinha leitora"
sync_all "$(D 3 800)"

# Publicações [INFO] (Dias 5 a 8): informações neutras e informações "virais" (rotas e abrigos)
# que após 24h viram MEMÓRIA INSTITUCIONAL consolidada para o comando `protocolo --usar-memoria`
post eva    "$(D 5 HOUR)" $'[INFO] Rio Madeira estavel hoje. Marca na regua da ponte: 4,2 m.\n'
INFO_NEUTRO=$HASH
post gisele "$(D 6 HOUR)" $'[INFO] ABRIGO enchente Rua Amazonas: Escola Municipal cadastrada (50 vagas, cozinha e gerador).\n'
INFO_ABRIGO=$HASH
post marcos "$(D 8 HOUR)" $'[INFO] ROTA DE FUGA enchente Rua Amazonas: Av. Madeira -> Morro do Cruzeiro (caminho alto, nunca alaga).\n'
INFO_ROTA=$HASH
sync_all "$(D 8 2*HOUR)"

# As postagens de rota e abrigo recebem vários likes (conteúdo "viral"), aumentando
# o `reps action` para que apareçam no topo das sugestões da memória institucional:
like fernando "$(D 9 100)" 1000 action "$INFO_ROTA"   "rota inspecionada e segura"
like eva      "$(D 9 200)"  800 action "$INFO_ROTA"   "confirmo, melhor caminho da Rua Amazonas"
like lucia    "$(D 9 300)"  300 action "$INFO_ROTA"   "muito util"
like fernando "$(D 9 400)" 1000 action "$INFO_ABRIGO" "abrigo oficial verificado"
sync_all "$(D 9 600)"

placar "$(D 14)"

# =============================================================================
titulo "SEMANAS 3-4 (Dias 15 a 28) — Newbie entra com --beg + 1º Ciclo de Alerta e [COLETA]"
# =============================================================================
# Henrique é morador novo (0 reps). Ele publica uma [INFO] usando `--beg`.
# O post fica pendente em `list begs` até que Gisele dá um like e o admite na chain.
beg henrique "$(D 16 HOUR)" $'[INFO] Sou novo na Rua Tapajos. Bueiro entupido na esquina com Rua Amazonas, alaga com chuva forte.\n'
BEG_HENRIQUE=$HASH
echo "-- begs pendentes no N2 (antes do like):"
FC --root="$N2" chain "$C" list begs
like gisele "$(D 16 2*HOUR)" 1500 action "$BEG_HENRIQUE" "informacao util, bem-vindo a comunidade"
echo "-- begs pendentes no N2 (após o like — esperado vazio):"
FC --root="$N2" chain "$C" list begs
sync_all "$(D 16 3*HOUR)"

# Dia 22: Primeiro alerta menor! Eva tem < 15.000 reps, então na UI o alerta nasce ⚪ PENDENTE.
post eva "$(D 22 HOUR)" $'[ALERTA] Chuva muito forte na cabeceira, rio subiu 40 cm em 6h perto da Rua Amazonas.\n'
ALERTA1=$HASH
sync_all "$(D 22 HOUR+300)"

# Gisele e Fernando (ambos com >= 10.000 reps, papel CONFIRMADOR) publicam [CONFIRMA <id>]
# e dão like no alerta -> com 2 confirmações válidas, o alerta sobe para 🚨 CONFIRMADO!
post gisele   "$(D 22 2*HOUR)"    "[CONFIRMA $(id12 "$ALERTA1")] Agua ja chegou ao meio-fio da Rua Amazonas."
like gisele   "$(D 22 2*HOUR+60)" 500 action "$ALERTA1" "confirmo o alerta"
post fernando "$(D 22 2*HOUR+120)" "[CONFIRMA $(id12 "$ALERTA1")] Confirmo na ponte, correnteza forte."
like fernando "$(D 22 2*HOUR+180)" 500 action "$ALERTA1" "confirmo o alerta"
sync_all "$(D 22 3*HOUR)"

# Coleta diária de reps ([COLETA]): Eva (emitiu alerta válido) e Gisele/Fernando (ajudaram)
# exercitam a coleta diária nas 24h seguintes, ganhando +1.000 reps pela consolidação!
post eva      "$(D 22 4*HOUR)" $'[COLETA] Coleta diaria de reps (emitiu alerta valido)\n'
post gisele   "$(D 22 4*HOUR+60)" $'[COLETA] Coleta diaria de reps (confirmou alerta)\n'
post fernando "$(D 22 4*HOUR+120)" $'[COLETA] Coleta diaria de reps (confirmou alerta)\n'
sync_all "$(D 22 5*HOUR)"

# Dia 23: Chuva passa e Fernando (COORDENADOR, >= 19.000 reps) encerra o alerta menor
post fernando "$(D 23 HOUR)" "[ENCERRA $(id12 "$ALERTA1")] Chuva cessou e nivel estabilizou. Sem desabrigados."
sync_all "$(D 23 2*HOUR)"

placar "$(D 28)"

# =============================================================================
titulo "SEMANAS 5-6 (Dias 29 a 42) — O Troll: Alarme Falso, Dislikes e Revogação"
# =============================================================================
# Dia 36: João (troll, < 10.000 reps) publica um [ALERTA] falso alarmista.
# Pela regra da aplicação, como João tem poucos reps, o alerta nasce apenas ⚪ PENDENTE (contendo o pânico).
post joao "$(D 36 HOUR)" $'[ALERTA] URGENTE! BARRAGEM ROMPEU A MONTANTE! FUJAM TODOS AGORA!\n'
FALSO1=$HASH
sync_all "$(D 36 HOUR+300)"

# Em vez de [CONFIRMA], o alerta falso recebe dislikes nos 3 nós e é REVOGADO (🚫 REVOGADO)
dislike fernando "$(D 36 2*HOUR)"     1000 action "$FALSO1" "falso, usina confirmou operacao normal"
dislike eva      "$(D 36 2*HOUR+60)"   800 action "$FALSO1" "falso, estou na beira do rio agora"
dislike marcos   "$(D 36 2*HOUR+120)"  500 action "$FALSO1" "mentira no porto"
revoke  defesa   "$(D 36 3*HOUR)"     1500 "$FALSO1" "alarme falso grave"
revoke  fernando "$(D 36 3*HOUR+60)"  1000 "$FALSO1" "conter panico"
sync_all "$(D 36 4*HOUR)"
echo "-- esperado: payload do alarme falso revogado (indisponível para get payload)"
ver "$FALSO1"

# Dia 40: João insiste espalhando boato como [INFO]; comunidade reage com dislikes no post e no autor
post joao "$(D 40 HOUR)" $'[INFO] Prefeitura esconde que o bairro inteiro vai afundar amanha. Compartilhem!\n'
FALSO2=$HASH
sync_all "$(D 40 HOUR+300)"
dislike gisele "$(D 40 2*HOUR)"    500 action "$FALSO2" "boato sem fundamento"
dislike lucia  "$(D 40 2*HOUR+60)" 200 action "$FALSO2" "desinformacao"
dislike fernando "$(D 41 HOUR)"   1000 author "$(kp joao)" "reincidente em alarmes falsos"
sync_all "$(D 41 2*HOUR)"

placar "$(D 42)"

# =============================================================================
titulo "SEMANA 7 (Dias 43 a 56) — Revogação Injusta, Unrevoke e Auto-Revogação"
# =============================================================================
# Dia 47: Marcos publica um [ALERTA] real sobre troncos gigantes descendo o rio
MSG_TRONCO=$'[ALERTA] Tronco gigante descendo o rio em alta velocidade, perigo para canoas no porto.\n'
echo -n "$MSG_TRONCO" > "$BASE/tronco.txt"
post marcos "$(D 47 HOUR)" "$MSG_TRONCO"
ALERTA_TRONCO=$HASH
sync_all "$(D 47 HOUR+300)"

# Igor, precipitado e achando que era mais um boato, gasta 1500 reps para revogar o alerta de Marcos
revoke igor "$(D 47 2*HOUR)" 1500 "$ALERTA_TRONCO" "achei que era boato"
sync_all "$(D 47 2*HOUR+300)"
echo "-- payload logo após o revoke precipitado de Igor (esperado: revogado):"
ver "$ALERTA_TRONCO"

# Fernando e Eva verificam o tronco no rio e usam `unrevoke` (com --file) + `like` para restaurar o alerta!
unrevoke fernando "$(D 47 3*HOUR)"     1500 "$ALERTA_TRONCO" --file="$BASE/tronco.txt" "perigo real confirmado"
unrevoke eva      "$(D 47 3*HOUR+60)"  1000 "$ALERTA_TRONCO" --file="$BASE/tronco.txt" "vi o tronco da margem"
sync_all "$(D 47 3*HOUR+90)"
like     gisele   "$(D 47 3*HOUR+120)" 1000 action "$ALERTA_TRONCO" "alerta real e importante" --file="$BASE/tronco.txt"
sync_all "$(D 47 4*HOUR)"
echo "-- esperado: payload restaurado após unrevoke da comunidade:"
ver "$ALERTA_TRONCO"

# Dia 49: Auto-revogação (direito ao esquecimento). Eva posta seu celular pessoal por engano e revoga em seguida.
post eva "$(D 49 HOUR)" $'[INFO] Meu telefone pessoal e (69) 99999-0000, me liguem qualquer hora.\n'
POST_FONE=$HASH
revoke eva "$(D 49 HOUR+120)" 1000 "$POST_FONE" "remocao de dado pessoal"
sync_all "$(D 49 2*HOUR)"

placar "$(D 56)"

# =============================================================================
titulo "SEMANAS 8-9 (Dias 57 a 69) — A GRANDE ENCHENTE (As 5 Fases da Aplicação)"
# =============================================================================
E=63   # Dia 63: início da Grande Enchente na Rua Amazonas

# --- FASE 1: EMISSÃO DO ALERTA ([ALERTA]) ------------------------------------
# Eva emite o alerta da enchente na Rua Amazonas.
post eva "$(D $E 0)" $'[ALERTA] Rio Madeira subiu 2 m em 3 h! Rua Amazonas alagada, agua no muro do posto de saude.\n'
ENCHENTE=$HASH
sync_all "$(D $E 300)"

# --- FASE 2: CONFIRMAÇÃO COMUNITÁRIA ([CONFIRMA <id>] + likes) ---------------
# Dois CONFIRMADORES (>= 10.000 reps: Fernando e Gisele) + Marcos confirmam o alerta.
# Na aplicação: 2+ confirmações de autores distintos com >= 10.000 reps -> 🚨 CONFIRMADO!
post fernando "$(D $E 900)"  "[CONFIRMA $(id12 "$ENCHENTE")] Confirmo no local. Rua Amazonas intransitavel, evacuacao imediata."
like fernando "$(D $E 960)"  1000 action "$ENCHENTE" "confirmo o alerta"
post gisele   "$(D $E 1100)" "[CONFIRMA $(id12 "$ENCHENTE")] Agua chegou na calçada da Escola Municipal."
like gisele   "$(D $E 1160)"  800 action "$ENCHENTE" "confirmo o alerta"
like marcos   "$(D $E 1250)"  600 action "$ENCHENTE" "confirmo subida rapida no porto"
sync_all "$(D $E 1500)"

# --- FASE 3: PROTOCOLO DE RESPOSTA COM MEMÓRIA ([PROTOCOLO <id>]) ------------
# Fernando (papel COORDENADOR, >= 19.000 reps) publica o protocolo puxando da
# memória institucional (`--usar-memoria`) a ROTA DE FUGA de Marcos e o ABRIGO de Gisele:
post fernando "$(D $E 1800)" "[PROTOCOLO $(id12 "$ENCHENTE")] Acionar Bombeiros 193 / Defesa Civil 199.
• ROTA DE FUGA enchente Rua Amazonas: Av. Madeira -> Morro do Cruzeiro (caminho alto, nunca alaga).
• ABRIGO enchente Rua Amazonas: Escola Municipal cadastrada (50 vagas, cozinha e gerador)."
PROTO=$HASH
sync_all "$(D $E 1900)"
like gisele "$(D $E 1950)" 1000 action "$PROTO" "protocolo em vigor"
sync_all "$(D $E 2100)"

# --- FASE 4: COORDENAÇÃO EM CAMPO ([COORD <id>]) E SABOTAGEM REVOGADA --------
post marcos   "$(D $E 2400)" "[COORD $(id12 "$ENCHENTE")] Levando barco para a Rua Amazonas. Preciso de 2 voluntarios no porto."
BARCO=$HASH
post gisele   "$(D $E 2700)" "[COORD $(id12 "$ENCHENTE")] Escola Municipal aberta como abrigo. 18 pessoas acolhidas ate agora."
ABRIGO_ABERTO=$HASH
post igor     "$(D $E 3000)" "[COORD $(id12 "$ENCHENTE")] Tenho lanterna e kit de primeiros socorros. Estou indo para a escola ajudar."
PROMESSA_IGOR=$HASH
post henrique "$(D $E 3300)" "[COORD $(id12 "$ENCHENTE")] SOS! Familia ilhada no telhado na Rua Tapajos 88 (2 criancas)!"
SOS_HENRIQUE=$HASH
sync_all "$(D $E 3600)"

like fernando "$(D $E 3700)" 1000 action "$SOS_HENRIQUE" "barco a caminho da Rua Tapajos 88"
like lucia    "$(D $E 3800)"  300 action "$BARCO"        "apoio aos barqueiros"
sync_all "$(D $E 4000)"

# Sabotagem durante a crise: João mente dizendo que o abrigo está lotado
post joao "$(D $E 4200)" "[COORD $(id12 "$ENCHENTE")] Nao venham para a Escola Municipal! Abrigo lotado e fechado!"
SABOTAGEM=$HASH
sync_all "$(D $E 4300)"

# Gisele e Fernando desmentem com dislike e revogam imediatamente a sabotagem
dislike gisele   "$(D $E 4400)"  800 action "$SABOTAGEM" "mentira, ainda temos 32 vagas no abrigo"
revoke  gisele   "$(D $E 4500)" 1000 "$SABOTAGEM" "sabotagem de abrigo em emergencia"
revoke  fernando "$(D $E 4600)" 1500 "$SABOTAGEM" "sabotagem perigosa"
sync_all "$(D $E 4800)"
echo "-- esperado: sabotagem revogada"
ver "$SABOTAGEM"

# Coleta diária ([COLETA]) liberada para quem contribuiu na emergência nas últimas 24h:
post eva      "$(D $E 5200)" $'[COLETA] Coleta diaria de reps (emitiu alerta confirmado da enchente)\n'
post fernando "$(D $E 5300)" $'[COLETA] Coleta diaria de reps (confirmou, publicou protocolo e coordenou)\n'
post gisele   "$(D $E 5400)" $'[COLETA] Coleta diaria de reps (confirmou e coordenou abrigo)\n'
post marcos   "$(D $E 5500)" $'[COLETA] Coleta diaria de reps (coordenou resgate de barco)\n'
post henrique "$(D $E 5600)" $'[COLETA] Coleta diaria de reps (coordenou SOS de familia ilhada)\n'
sync_all "$(D $E 6000)"

# Dia 64: Encerramento oficial da emergência ([ENCERRA <id>]) pelo COORDENADOR Fernando
post fernando "$(D $((E+1)) HOUR)" "[ENCERRA $(id12 "$ENCHENTE")] Todos os moradores ilhados foram resgatados. 34 pessoas abrigadas com seguranca na Escola Municipal."
FIM_ENCHENTE=$HASH
sync_all "$(D $((E+1)) 2*HOUR)"
like eva "$(D $((E+1)) 2*HOUR+300)" 800 action "$FIM_ENCHENTE" "resgate concluido"
sync_all "$(D $((E+1)) 3*HOUR)"

placar "$(D $((E+2)))"

# =============================================================================
titulo "SEMANA 10 (Dia 70) — Fase 5: Avaliação Pós-Emergência dos Participantes"
# =============================================================================
# A aplicação (`alerta.py participantes <id>`) lista quem atuou no alerta da enchente
# (ALERTA, CONFIRMA, PROTOCOLO, COORD, ENCERRA) para que a comunidade avalie as PESSOAS:
# - Defesa Civil, Eva e Gisele premiam Fernando para reconsolidá-lo como COORDENADOR (>= 19k)
# - Defesa Civil e Fernando premiam Gisele e Marcos para promovê-los a CONFIRMADOR (>= 10k)
like    defesa   "$(D 70 50)"  9500 author "$(kp fernando)" "coordenacao exemplar da emergencia"
like    eva      "$(D 70 100)" 3500 author "$(kp fernando)" "coordenou o resgate e protocolo com precisao"
like    gisele   "$(D 70 200)" 1200 author "$(kp fernando)" "liderou a resposta na Rua Amazonas"
like    defesa   "$(D 70 250)" 6000 author "$(kp gisele)"   "gestao impecavel do abrigo oficial"
like    fernando "$(D 70 300)" 1500 author "$(kp gisele)"   "organizacao impecavel do abrigo na escola"
like    lucia    "$(D 70 350)"  400 author "$(kp marcos)"   "resgatou minha familia de barco"
like    fernando "$(D 70 400)" 1500 author "$(kp marcos)"   "barco salvou 12 moradores ilhados"
like    gisele   "$(D 70 600)" 1000 author "$(kp eva)"      "alerta rapido evitou tragedia"
like    fernando "$(D 70 700)" 1000 author "$(kp henrique)" "SOS na Rua Tapajos salvou 2 criancas"

# Igor prometeu levar lanterna e kit de socorros ([COORD]), mas não apareceu:
dislike gisele   "$(D 70 800)"  800 author "$(kp igor)"     "prometeu kit de socorro e nao compareceu"
dislike fernando "$(D 70 900)"  500 action "$PROMESSA_IGOR" "nao apareceu no abrigo"
sync_all "$(D 70 1200)"

placar "$(D 77)"

# =============================================================================
titulo "SEMANAS 11-13 (Dias 78 a 92) — Retorno à Rotina, Redenção e Nova Memória"
# =============================================================================
# Postagens [INFO] atualizam a memória institucional para futuras cheias
post marcos   "$(D 80 HOUR)" $'[INFO] Nivel do Rio Madeira voltou a 4,4 m. Rota Av. Madeira totalmente limpa.\n'
sync_all "$(D 80 2*HOUR)"
post gisele   "$(D 84 HOUR)" $'[INFO] ABRIGO Escola Municipal recebeu doacao de 40 colchoes novos e 2 barcos inflaveis.\n'
sync_all "$(D 84 2*HOUR)"
post henrique "$(D 86 HOUR)" $'[INFO] Prefeitura desentupiu o bueiro da Rua Tapajos com Rua Amazonas.\n'
sync_all "$(D 86 2*HOUR)"

# Redenção de Igor: pede desculpas e entrega o kit de primeiros socorros na escola
post igor     "$(D 88 HOUR)" $'[INFO] Peco desculpas por ter falhado na enchente. Entreguei o kit de socorro e 2 lanternas na Escola Municipal.\n'
REDENCAO=$HASH
sync_all "$(D 88 2*HOUR)"
like gisele   "$(D 88 3*HOUR)" 300 action "$REDENCAO" "recebido na escola, obrigado"
like lucia    "$(D 88 3*HOUR+60)" 100 action "$REDENCAO" "valeu"
sync_all "$(D 88 4*HOUR)"

# Dia 91: Relatório final de memória institucional ([INFO])
post fernando "$(D 91 HOUR)" $'[INFO] MEMORIA DA ENCHENTE: Rota Av. Madeira -> Morro do Cruzeiro e Abrigo Escola Municipal salvaram 34 pessoas.\n'
MEMORIA_FINAL=$HASH
sync_all "$(D 91 HOUR+300)"
like eva    "$(D 91 2*HOUR)" 600 action "$MEMORIA_FINAL" "registro historico"
like gisele "$(D 91 3*HOUR)" 600 action "$MEMORIA_FINAL" "confirmado"
sync_all "$(D 91 4*HOUR)"

# =============================================================================
titulo "RESULTADO FINAL DA SIMULAÇÃO (Dia 92 — 3 Meses Completos)"
# =============================================================================
TF=$(D 92)
placar "$TF"
FC --root="$N1" --now="$TF" chain "$C" reps actions     # reputação de todos os posts
FC --root="$N1" chain "$C" list revokes                 # posts revogados (alarmes falsos / fone)
FC --root="$N1" chain "$C" list order                   # ordem de consenso
FC --root="$N1" chain "$C" list dag                     # DAG completo em ASCII

# Verificação de convergência P2P entre os 3 nós
echo "-- Hash MD5 da ordem de consenso nos 3 nós (devem ser idênticos):"
for n in "$N1" "$N2" "$N3"; do
    "$FREECHAINS" --root="$n" chain "$C" list order | md5sum
done

# Encerra os daemons em background
pkill -f "base-path=$BASE" 2>/dev/null || true
titulo "FIM"
