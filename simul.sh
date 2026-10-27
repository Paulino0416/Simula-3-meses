#!/usr/bin/env bash
# =============================================================================
#  Simulação de 3 meses da chain '#alertas-rio-madeira' (Freechains v0.20)
#
#  Aplicação: Sistema Comunitário de Alerta e Resposta a Emergências.
#  A aplicação é uma camada de UI sobre o Freechains: ela apenas LÊ reps,
#  likes, dislikes e revogações. Nenhuma regra do protocolo é alterada.
#
#  - 3 nós (peers), cada um com seu próprio --root e daemon
#  - 9 usuários com perfis diferentes, divididos entre os nós
#  - Passagem de tempo simulada com --now=<secs> (13 semanas)
#  - Sincronização em malha após cada dia de atividade (evita hard forks,
#    que ocorrem quando ramos divergem por 7 dias ou 100 ações)
#
#  Requisitos: git, openssh-client, lua5.4, freechains v0.20
#     sudo luarocks --lua-version=5.4 install freechains
#  Uso:  bash simul.sh | tee simul.log
# =============================================================================

set -uo pipefail     # sem -e: erros esperados (ex.: post sem reps) não abortam

FREECHAINS=${FREECHAINS:-freechains}

# --- wrappers ---------------------------------------------------------------
# FC  : executa e mostra o comando (falhas são registradas, não abortam)
# FCH : idem, e guarda em $HASH o id impresso na última linha
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
titulo () { echo; echo "################ $* ################"; echo; }

# --- diretórios, nós e portas ----------------------------------------------
BASE=/tmp/simul-alertas
KEYS=$BASE/keys
N1=$BASE/N1      # Nó 1: sede da Defesa Civil (centro)
N2=$BASE/N2      # Nó 2: bairro Rua Amazonas
N3=$BASE/N3      # Nó 3: comunidade ribeirinha (beira do rio)
P1=8401; P2=8402; P3=8403
C='#alertas-rio-madeira'

pkill -f "base-path=$BASE" 2>/dev/null || true   # mata daemons de execuções antigas
sleep 1
rm -rf "$BASE"
mkdir -p "$N1" "$N2" "$N3" "$KEYS"

# --- tempo simulado ----------------------------------------------------------
T0=1790000000          # "dia 0" da simulação (epoch)
DAY=86400
HOUR=3600
D () { echo $(( T0 + $1*DAY + ${2:-0} )); }   # D <dia> [segundos] -> epoch

# --- usuários (perfis) -------------------------------------------------------
#  defesa   : pioneira institucional (Defesa Civil)            -> N1
#  fernando : voluntário muito ativo / coordenador             -> N1
#  eva      : moradora atenta, emite alertas reais             -> N2
#  gisele   : diretora da escola (abrigo), confirmadora        -> N2
#  henrique : newbie, entra sem reps (usa --beg)               -> N2
#  marcos   : barqueiro, posta rotas úteis (conteúdo "viral")  -> N3
#  joao     : troll, emite alarmes falsos                      -> N3
#  igor     : promete e não aparece (pouco confiável)          -> N3
#  lucia    : moradora passiva, quase só lê e às vezes curte   -> N3
for u in defesa fernando eva gisele henrique marcos joao igor lucia; do
    ssh-keygen -t ed25519 -C '' -N '' -q -f "$KEYS/$u"
done
k () { echo "$KEYS/$1"; }          # chave privada
kp () { echo "$KEYS/$1.pub"; }     # chave pública

# root de cada usuário (nó onde ele opera)
root_of () {
    case $1 in
        defesa|fernando)        echo "$N1" ;;
        eva|gisele|henrique)    echo "$N2" ;;
        *)                      echo "$N3" ;;
    esac
}

# --- ações em alto nível ------------------------------------------------------
# post <user> <t> <texto>            -> HASH
# like/dislike <user> <t> <n> action|author <alvo>
# revoke/unrevoke <user> <t> <n> <id>
post ()     { FCH --root="$(root_of "$1")" --now="$2" chain "$C" post inline "$3" --sign="$(k "$1")"; }
beg ()      { FCH --root="$(root_of "$1")" --now="$2" chain "$C" post inline "$3" --beg --sign="$(k "$1")"; }
like ()     { FC  --root="$(root_of "$1")" --now="$2" chain "$C" like    "$3" "$4" "$5" --sign="$(k "$1")" ${6:+--why="$6"} ${7:+"$7"}; }
dislike ()  { FC  --root="$(root_of "$1")" --now="$2" chain "$C" dislike "$3" "$4" "$5" --sign="$(k "$1")" ${6:+--why="$6"}; }
revoke ()   { FC  --root="$(root_of "$1")" --now="$2" chain "$C" revoke   "$3" "$4" --sign="$(k "$1")"; }
unrevoke () { FC  --root="$(root_of "$1")" --now="$2" chain "$C" unrevoke "$3" "$4" --sign="$(k "$1")" ${5:+"$5"}; }

# sync <t> : malha completa (cada nó recebe dos outros dois), em duas rodadas
#            para que tudo chegue a todos.
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

# placar: reputação de todos os autores, vista a partir do N1
placar () {
    echo "---- reps em $(date -u -d "@$1" +%F 2>/dev/null || echo "$1") ----"
    FC --root="$N1" --now="$1" chain "$C" reps authors
    for u in defesa fernando eva gisele henrique marcos joao igor lucia; do
        printf '%-9s ' "$u"
        "$FREECHAINS" --root="$N1" --now="$1" chain "$C" reps author "$(kp "$u")" 2>/dev/null || echo "?"
    done
}

# payload visível ou revogado?
ver () { FC --root="$N1" chain "$C" get payload "$1"; }

# =============================================================================
titulo "SEMANA 0 — criação da chain e dos nós"
# =============================================================================
# A Defesa Civil é a única pioneira: recebe a carga inicial de reps (Regra 1.a)
FC --root="$N1" --now="$(D 0)" chains add "$C" init --pioneer="$(kp defesa)"
FC --root="$N1" daemon start --port=$P1 -- --listen=127.0.0.1 --reuseaddr &
sleep 1

# N2 e N3 entram clonando de N1 — entrada livre, sem pedir permissão
FC --root="$N2" chains add "$C" clone localhost:$P1
FC --root="$N3" chains add "$C" clone localhost:$P1

# Agora que N2/chains e N3/chains existem, cada nó serve a chain em sua porta
FC --root="$N2" daemon start --port=$P2 -- --listen=127.0.0.1 --reuseaddr &
FC --root="$N3" daemon start --port=$P3 -- --listen=127.0.0.1 --reuseaddr &
sleep 1

# Primeiro post: regras da comunidade (netiqueta de moderação)
post defesa "$(D 0 600)" $'[REGRAS] Canal de alertas do Rio Madeira.\nPoste so o que viu. Alertas falsos serao revogados.\n'
REGRAS=$HASH

# --- teste não-permissionado: chave nova sem reps NÃO consegue postar --------
echo "-- esperado: falha (joao ainda tem 0 reps)"
post joao "$(D 0 900)" $'oi gente\n'

sync_all "$(D 0 1200)"

# =============================================================================
titulo "SEMANAS 1-2 — semeadura de confiança (boas-vindas)"
# =============================================================================
# A pioneira distribui reps a quem a comunidade conhece no mundo real.
# like ... author = valor inteiro vai para a pessoa (menos taxa de 10%).
like defesa "$(D 1 100)" 16000 author "$(kp fernando)" "enfermeiro voluntario e coordenador"
like defesa "$(D 1 200)" 10000 author "$(kp eva)"      "lider de rua"
like defesa "$(D 1 300)"  8000 author "$(kp gisele)"   "diretora da escola"
like defesa "$(D 1 400)"  5000 author "$(kp marcos)"   "barqueiro"
sync_all "$(D 1 600)"

# Fernando (já com reps) recebe outros moradores — permissionless:
# qualquer membro pode acolher qualquer recém-chegado
like fernando "$(D 3 100)" 3000 author "$(kp joao)"  "morador ribeirinho"
like fernando "$(D 3 200)" 3000 author "$(kp igor)"  "disse que tem kit de socorro"
like eva      "$(D 3 300)" 2000 author "$(kp lucia)" "vizinha"
sync_all "$(D 3 600)"

# Posts neutros/informativos (rotina) — custam reps temporariamente
post eva    "$(D 5 HOUR)"     $'Rio estavel hoje. Marca na ponte: 4,2 m.\n'
NEUTRO1=$HASH
post gisele "$(D 6 HOUR)"     $'Escola Municipal cadastrada como abrigo. Capacidade: 50 pessoas.\n'
ABRIGO=$HASH
post marcos "$(D 8 HOUR)"     $'ROTA DE FUGA: Av. Madeira -> Morro do Cruzeiro (sempre seca).\n'
ROTA=$HASH
sync_all "$(D 8 2*HOUR)"

# Conteúdo útil ("viral"): vários likes em post (metade p/ post, metade p/ autor)
like fernando "$(D 9 100)" 1000 action "$ROTA"   "rota testada"
like eva      "$(D 9 200)"  800 action "$ROTA"   "confirmo, e segura"
like lucia    "$(D 9 300)"  300 action "$ROTA"
like defesa   "$(D 9 400)" 1000 action "$ABRIGO" "abrigo oficial"
sync_all "$(D 9 600)"

placar "$(D 14)"

# =============================================================================
titulo "SEMANAS 3-4 — newbie entra pedindo (beg) + primeiro alerta menor"
# =============================================================================
# Henrique é novo, sem reps: posta com --beg. O post fica fora da chain
# (refs/begs) até alguém com reps curtir — curtir o beg admite post e autor.
beg henrique "$(D 16 HOUR)" $'Sou novo na Rua Tapajos. Bueiro entupido na esquina, alaga com chuva.\n'
BEG=$HASH
FC --root="$N2" chain "$C" list begs
like gisele "$(D 16 2*HOUR)" 1500 action "$BEG" "informacao util, bem-vindo"
FC --root="$N2" chain "$C" list begs     # esperado: vazio
sync_all "$(D 16 3*HOUR)"

# Alerta menor de Eva (chuva forte) com confirmação de Gisele
post eva    "$(D 22 HOUR)"   $'[ATENCAO] Chuva forte, rio subiu 40 cm em 6h. Monitorando.\n'
ALERTA_MENOR=$HASH
sync_all "$(D 22 HOUR+600)"
post gisele "$(D 22 2*HOUR)" $'Confirmo: agua no meio-fio da Rua Amazonas.\n'
like gisele "$(D 22 2*HOUR+60)" 500 action "$ALERTA_MENOR" "confirmado"
like fernando "$(D 22 3*HOUR)"  500 action "$ALERTA_MENOR" "confirmado"
sync_all "$(D 22 4*HOUR)"

placar "$(D 28)"

# =============================================================================
titulo "SEMANAS 5-6 — o troll: alarme falso, dislikes e revogação"
# =============================================================================
# João posta um alarme falso para causar pânico (ele tem reps, então consegue)
post joao "$(D 36 HOUR)" $'[URGENTE] BARRAGEM ROMPEU!!! FUJAM TODOS AGORA!!!\n'
FALSO=$HASH
sync_all "$(D 36 HOUR+300)"

# Moradores verificam (não há barragem rompida) e reagem com dislikes
dislike fernando "$(D 36 2*HOUR)"     1000 action "$FALSO" "nao existe barragem rompida"
dislike eva      "$(D 36 2*HOUR+60)"   800 action "$FALSO" "falso, estou no rio agora"
dislike marcos   "$(D 36 2*HOUR+120)"  500 action "$FALSO" "falso"
# ... e a Defesa Civil revoga o conteúdo (payload some, metadados ficam no DAG)
revoke defesa    "$(D 36 3*HOUR)"     2000 "$FALSO"
revoke fernando  "$(D 36 3*HOUR+60)"  1000 "$FALSO"
sync_all "$(D 36 4*HOUR)"
echo "-- esperado: payload revogado"
ver "$FALSO"

# João insiste com outro post de pânico; Gisele e Lucia dão dislike
post joao "$(D 40 HOUR)" $'Prefeitura esconde que a cidade vai afundar. Compartilhem!\n'
FALSO2=$HASH
sync_all "$(D 40 HOUR+300)"
dislike gisele "$(D 40 2*HOUR)" 500 action "$FALSO2" "boato"
dislike lucia  "$(D 40 2*HOUR+60)" 200 action "$FALSO2"
sync_all "$(D 40 3*HOUR)"

# Dislike direto no autor (avaliação da pessoa, não do post)
dislike defesa "$(D 41 HOUR)" 1000 author "$(kp joao)" "reincidente em alarmes falsos"
sync_all "$(D 41 2*HOUR)"

placar "$(D 42)"

# =============================================================================
titulo "SEMANA 7 — revogação injusta e unrevoke"
# =============================================================================
# Igor, achando que era boato, revoga um alerta REAL de Marcos
post marcos "$(D 47 HOUR)" $'Tronco grande descendo o rio, perigo para canoas perto do porto.\n'
TRONCO=$HASH
sync_all "$(D 47 HOUR+300)"
revoke igor "$(D 47 2*HOUR)" 1500 "$TRONCO"
sync_all "$(D 47 2*HOUR+300)"
echo "-- payload após o revoke de Igor:"
ver "$TRONCO"

# A comunidade comprova o perigo e restaura o conteúdo (passando o payload original)
echo -n $'Tronco grande descendo o rio, perigo para canoas perto do porto.\n' > "$BASE/tronco.txt"
unrevoke fernando "$(D 47 3*HOUR)"     1500 "$TRONCO" --file="$BASE/tronco.txt"
unrevoke eva      "$(D 47 3*HOUR+60)"  1000 "$TRONCO" --file="$BASE/tronco.txt"
sync_all "$(D 47 3*HOUR+90)"
like     defesa   "$(D 47 3*HOUR+120)" 1000 action "$TRONCO" "alerta real, bem feito" --file="$BASE/tronco.txt"
sync_all "$(D 47 4*HOUR)"
echo "-- esperado: payload restaurado"
ver "$TRONCO"

# Post pessoal de que Eva se arrepende: auto-revogação (gratuita e absoluta)
post eva "$(D 49 HOUR)" $'Meu telefone e 69 9xxxx-xxxx, liguem se precisarem.\n'
ARREP=$HASH
revoke eva "$(D 49 HOUR+120)" 1000 "$ARREP"
sync_all "$(D 49 2*HOUR)"

placar "$(D 56)"

# =============================================================================
titulo "SEMANAS 8-9 — A GRANDE ENCHENTE (cenário principal da aplicação)"
# =============================================================================
E=63   # dia da enchente

# Fase 1 — Emissão: Eva (reps altos) -> a UI exibe como ALERTA ATIVO
post eva "$(D $E 0)" $'[URGENTE] Rio subiu 2 m em 3 h. Rua Amazonas alagada.\nAgua no muro do posto de saude.\n'
ENCHENTE=$HASH
sync_all "$(D $E 300)"

# Fase 2 — Confirmação: posts filhos no DAG + likes no post de Eva
post fernando "$(D $E 900)"  $'Confirmo. Estou na Rua Amazonas. Agua ja na escola. Evacuacao necessaria.\n'
CONF1=$HASH
like fernando "$(D $E 960)"  1000 action "$ENCHENTE" "confirmo no local"
like gisele   "$(D $E 1200)"  800 action "$ENCHENTE" "confirmo"
like marcos   "$(D $E 1300)"  500 action "$ENCHENTE" "confirmo pelo rio"
sync_all "$(D $E 1500)"
# (UI: 2+ likes de membros com reps altos -> ALERTA CONFIRMADO)

# Fase 3 — Protocolo de resposta (ação humana, sugerida pela UI que
# recupera do DAG a rota e o abrigo consolidados semanas antes)
post fernando "$(D $E 1800)" $'PROTOCOLO: Rota Av. Madeira -> Morro do Cruzeiro.\nAbrigo: Escola Municipal (50 vagas). Bombeiros 193 / Defesa Civil 199.\n'
PROTO=$HASH
sync_all "$(D $E 1850)"
like defesa "$(D $E 1900)" 1500 action "$PROTO" "protocolo oficial"
sync_all "$(D $E 2100)"

# Fase 4 — Coordenação na chain pública
post marcos   "$(D $E 2400)" $'Levando barco para a Rua Amazonas. Preciso de mais 2 voluntarios.\n'
BARCO=$HASH
post gisele   "$(D $E 2700)" $'Escola aberta como abrigo. 12 pessoas ate agora.\n'
ESCOLA=$HASH
post igor     "$(D $E 3000)" $'Tenho lanterna e kit de primeiros socorros. Indo para a escola.\n'
PROMESSA=$HASH
post henrique "$(D $E 3300)" $'Familia ilhada na Rua Tapajos 88, 2 criancas!\n'
SOS=$HASH
sync_all "$(D $E 3600)"
# Henrique já foi admitido na Semana 3 e possui reps, então posta normalmente.
# Fernando e Lucia curtem as ações de resgate:
like fernando "$(D $E 3700)" 1000 action "$SOS" "indo resgatar"
like lucia    "$(D $E 3800)"  200 action "$BARCO"
sync_all "$(D $E 4000)"

# Troll aproveita o caos — dislike imediato e revogação
post joao "$(D $E 4200)" $'Abrigo da escola esta cheio, nao venham!\n'
SABOTA=$HASH
sync_all "$(D $E 4300)"
dislike gisele "$(D $E 4400)" 800 action "$SABOTA" "mentira, temos vagas"
revoke  gisele "$(D $E 4500)" 1000 "$SABOTA"
revoke  defesa "$(D $E 4600)" 1500 "$SABOTA"
sync_all "$(D $E 5000)"
echo "-- esperado: sabotagem revogada"
ver "$SABOTA"

# Encerramento (dia seguinte)
post fernando "$(D $((E+1)) HOUR)" $'ENCERRAMENTO: todos resgatados. 31 pessoas abrigadas na escola.\n'
FIM=$HASH
like defesa "$(D $((E+1)) 2*HOUR)" 1000 action "$FIM"
sync_all "$(D $((E+1)) 3*HOUR)"

placar "$(D $((E+2)))"

# =============================================================================
titulo "SEMANA 10 — Fase 5: avaliação pós-emergência"
# =============================================================================
# A UI lista quem participou (lendo o DAG entre ENCHENTE e FIM).
# Avaliação de pessoas: like/dislike ... author
like    eva      "$(D 70 100)" 1500 author "$(kp fernando)" "coordenou o resgate"
like    gisele   "$(D 70 200)" 1000 author "$(kp fernando)" "coordenou o resgate"
like    lucia    "$(D 70 300)"  300 author "$(kp marcos)"   "me tirou de barco"
like    fernando "$(D 70 400)" 1500 author "$(kp marcos)"   "barco salvou 12 pessoas"
like    defesa   "$(D 70 500)" 2000 author "$(kp gisele)"   "abrigo impecavel"
like    fernando "$(D 70 600)"  800 author "$(kp henrique)" "alerta da familia salvou vidas"
dislike gisele   "$(D 70 700)"  800 author "$(kp igor)"     "prometeu e nao apareceu"
dislike fernando "$(D 70 800)"  500 action "$PROMESSA"      "nao veio"
sync_all "$(D 70 1000)"

placar "$(D 77)"

# =============================================================================
titulo "SEMANAS 11-13 — rotina e memória institucional"
# =============================================================================
# Posts neutros mantêm a chain viva; consolidação recompensa autores ativos.
post marcos   "$(D 80 HOUR)" $'Nivel do rio voltou a 4,5 m. Rota Av. Madeira liberada.\n'
post gisele   "$(D 84 HOUR)" $'Escola recebeu doacoes: 40 colchoes para o proximo abrigo.\n'
post henrique "$(D 86 HOUR)" $'Bueiro da Rua Tapajos foi limpo pela prefeitura.\n'
post igor     "$(D 88 HOUR)" $'Desculpem pela ultima vez. Kit de socorro agora fica na escola.\n'
REDENCAO=$HASH
like lucia    "$(D 88 2*HOUR)" 100 action "$REDENCAO" "valeu"
sync_all "$(D 88 3*HOUR)"

post fernando "$(D 91 HOUR)" $'[MEMORIA] Licoes da enchente: rota Av. Madeira e escola funcionaram.\n'
LICOES=$HASH
sync_all "$(D 91 HOUR+300)"
like eva    "$(D 91 2*HOUR)" 500 action "$LICOES"
like defesa "$(D 91 3*HOUR)" 500 action "$LICOES"
sync_all "$(D 91 4*HOUR)"

# =============================================================================
titulo "RESULTADO FINAL (dia 92)"
# =============================================================================
TF=$(D 92)
placar "$TF"
FC --root="$N1" --now="$TF" chain "$C" reps actions     # reputação dos posts
FC --root="$N1" chain "$C" list revokes                 # posts revogados
FC --root="$N1" chain "$C" list order                   # ordem de consenso
FC --root="$N1" chain "$C" list dag                     # DAG completo

# Os 3 nós devem ter o mesmo estado (convergência P2P)
echo "-- ordem nos 3 nós (devem ser iguais):"
for n in "$N1" "$N2" "$N3"; do
    "$FREECHAINS" --root="$n" chain "$C" list order | md5sum
done

# encerra daemons
pkill -f "base-path=$BASE" 2>/dev/null || true
titulo "FIM"
