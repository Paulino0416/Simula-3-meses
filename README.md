# Simulação de 3 Meses: Sistema Comunitário de Alerta e Resposta a Emergências (Freechains v0.20)

Este repositório contém a simulação reproduzível de **3 meses (92 dias / 13 semanas)** da cadeia pública `#alertas-rio-madeira` sobre o **Freechains v0.20** ([documentação da CLI v0.20](https://github.com/Freechains/freechains.vcs/blob/v0.20/cli.md)), utilizando `--now=<secs>` para controlar a passagem do tempo em **3 nós P2P** independentes com **9 usuários** divididos entre eles.

A simulação implementa e exercita diretamente a arquitetura, as convenções de mensagens, os limiares de reputação, os papéis de usuários e o ciclo de 5 fases da aplicação final da disciplina (**Pergunta #5**): o **Sistema Comunitário de Alerta e Resposta a Emergências** (`alerta.py` / interface web — [repositório da aplicação](https://github.com/Paulino0416/Aplica-o-Freechains)).

## Como reproduzir a simulação

```bash
# 1. Instalar dependências (Ubuntu / Debian / WSL)
sudo apt update && sudo apt install -y git openssh-client lua5.4 luarocks
sudo luarocks --lua-version=5.4 install freechains

# 2. Executar o script de simulação (gera também o log completo)
bash simul.sh | tee simul.log
```

---

## a. Introdução ao problema e intenção da aplicação

Em comunidades ribeirinhas do Rio Madeira (como o bairro da Rua Amazonas), enchentes súbitas frequentemente derrubam provedores centralizados de internet no momento mais crítico. Além disso, grupos de mensagens convencionais sofrem com três problemas graves durante emergências:
1. **Pânico causado por boatos e sabotagem**: alarmes falsos (*"a barragem rompeu!"*) ou sabotagens (*"o abrigo está lotado, não venham!"*) espalham-se sem filtro de confiabilidade.
2. **Ausência de triagem por reputação**: alertas reais de moradores experientes na beira do rio têm o mesmo destaque visual que mensagens de contas recém-criadas (ataques Sybil) ou trolls.
3. **Perda de memória institucional**: rotas de fuga seguras e abrigos comunitários validados em cheias anteriores se perdem no histórico e precisam ser redescobertos a cada nova crise.

### Intenção da aplicação (Pergunta #5)

A aplicação (`alerta.py` + interface web) funciona como uma **camada de interpretação e coordenação sobre o Freechains v0.20**, **sem alterar o protocolo**. Ela utiliza uma convenção de tags em texto puro no payload dos posts e calcula estados e papéis lendo `reps author`, `reps action`, `list order`, `list begs` e `list revokes`:

#### 1. Convenção de tags no payload
- `[ALERTA] <texto>`: emite um alerta de emergência.
- `[CONFIRMA <id12>] <texto>`: confirma presencialmente um alerta (acompanhado de `like` no post do alerta).
- `[PROTOCOLO <id12>] <texto>`: publica o protocolo oficial de resposta, resgatando rotas e abrigos consolidados na **memória institucional** (`--usar-memoria`).
- `[COORD <id12>] <texto>`: mensagens de coordenação em campo (barcos de resgate, vagas no abrigo, pedidos de SOS).
- `[ENCERRA <id12>] <texto>`: encerra formalmente a emergência e abre a fase de avaliação dos participantes.
- `[INFO] <texto>`: informação de rotina (medições do rio, cadastro de rotas de fuga e abrigos); após **24h** sem ser revogada, torna-se **memória institucional consolidada**.
- `[COLETA] <texto>`: registro da **coleta diária de reputação** (`1x/dia`, gerando `+1.000 reps` após 24h pela consolidação do protocolo), liberada na aplicação **exclusivamente para quem contribuiu nas últimas 24h** (emitindo um alerta válido ou ajudando no alerta de outra pessoa com `CONFIRMA`, `PROTOCOLO`, `COORD` ou `ENCERRA`).

#### 2. Estados de alerta e papéis por reputação na aplicação

| Conceito na Aplicação | Regra / Limiar lido do Freechains v0.20 | Efeito na Interface e Operação |
|---|---|---|
| **Papel: `membro`** | `< 10.000 reps` | Pode emitir alertas (que nascem `⚪ PENDENTE`), coordenar (`[COORD]`) e votar. Novatos sem reps entram via `--beg`. |
| **Papel: `CONFIRMADOR`** | `>= 10.000 reps` | Suas postagens `[CONFIRMA <id>]` contam para validar alertas pendentes. |
| **Papel: `COORDENADOR`** | `>= 19.000 reps` | Único papel autorizado a publicar o `[PROTOCOLO <id>]` de resposta e a publicar `[ENCERRA <id>]` em emergências ativas/confirmadas. |
| **Estado: `⚪ PENDENTE`** | Autor com `< 15.000 reps` e `< 2` confirmações válidas | Alerta exibido em cinza, aguardando verificação de confirmadores (contém o pânico de trolls). |
| **Estado: `🔴 ATIVO`** | Autor com `>= 15.000 reps` | Alerta de emissor altamente confiável já nasce ativo em destaque. |
| **Estado: `🚨 CONFIRMADO`** | `2+` posts `[CONFIRMA]` de autores distintos com `>= 10.000 reps` | Emergência confirmada; habilita a publicação do `[PROTOCOLO]` com memória da comunidade. |
| **Estado: `✅ ENCERRADO`** | Post `[ENCERRA <id>]` por um `COORDENADOR` (`>= 19.000 reps`) | Crise concluída; habilita a listagem de `participantes` para avaliação pós-emergência. |
| **Estado: `🚫 REVOGADO`** | `get payload` falha (revogado via `chain revoke`) | Alarme falso ou sabotagem ocultado na UI, mantendo os metadados auditáveis no DAG (`~id~`). |

#### 3. Topologia P2P: 3 nós e 9 usuários

Os **9 usuários** estão distribuídos entre **3 nós P2P** independentes (`N1`, `N2` e `N3`), cada um rodando seu próprio `freechains daemon` e sincronizando em malha (`chain sync recv`) com `--now=<secs>` para evitar *hard forks* (divergências superiores a 7 dias ou 100 ações):

| Nó | Localização | Porta | Usuários Alocados |
|---|---|---|---|
| **N1** | Sede da Defesa Civil (Centro) | `8401` | `defesa` (pioneira), `fernando` |
| **N2** | Bairro Rua Amazonas (Escola/Abrigo) | `8402` | `eva`, `gisele`, `henrique` |
| **N3** | Comunidade Ribeirinha (Porto) | `8403` | `marcos`, `joao`, `igor`, `lucia` |

---

## b. Natureza das mensagens postadas por cada tipo de autor

A simulação varia o perfil social, a frequência de postagem e a qualidade das mensagens entre os 9 usuários ao longo das 13 semanas:

| Usuário | Nó | Perfil | Natureza das Mensagens Publicadas na Simulação |
|---|---|---|---|
| **`defesa`** | N1 | **Pioneira Institucional / Moderadora** | Inicializa a chain (`--pioneer`) com 30.000 reps. Publica `[INFO]` com as regras do canal e monitoramento hidrológico, realiza a semeadura inicial de reputação para estruturar os papéis de `COORDENADOR` e `CONFIRMADOR`, e atua na moderação revogando alarmes falsos graves. |
| **`fernando`** | N1 | **Coordenador Ativo (`COORDENADOR`)** | Enfermeiro voluntário de altíssima atividade. Confirma alertas em campo (`[CONFIRMA]`), publica o **`[PROTOCOLO]` de resposta** na Grande Enchente resgatando a rota e o abrigo da memória institucional, faz coletas diárias legítimas (`[COLETA]`), publica o **`[ENCERRA]`** das duas emergências e registra o relatório final de lições aprendidas (`[INFO]`). |
| **`eva`** | N2 | **Emissora Confiável (Líder de Rua)** | Moradora atenta da Rua Amazonas. Publica medições neutras do rio (`[INFO]`), emite o **1º `[ALERTA]` menor** de chuva forte (Semana 4) e o **`[ALERTA]` principal da Grande Enchente** (Semana 9), realiza coletas diárias (`[COLETA]`) após emitir alertas válidos e faz um post pessoal com seu telefone do qual se arrepende e auto-revoga (Semana 7). |
| **`gisele`** | N2 | **Confirmadora e Gestora de Abrigo (`CONFIRMADOR`)** | Diretora da Escola Municipal. Publica o cadastro da escola como abrigo para 50 pessoas (`[INFO]` que vira memória institucional), confirma presencialmente os alertas de `eva` (`[CONFIRMA]`), coordena a abertura e ocupação do abrigo (`[COORD]`), coleta reps diários (`[COLETA]`) e informa a chegada de doações pós-crise (`[INFO]`). |
| **`marcos`** | N3 | **Autor de Conteúdo "Viral" (Barqueiro)** | Barqueiro experiente do porto. Publica a **`[INFO]` da Rota de Fuga segura** (`Av. Madeira -> Morro do Cruzeiro`), que viraliza em curtidas e é puxada para o protocolo da enchente; emite o `[ALERTA]` real de um tronco gigante descendo o rio (Semana 7); coordena o resgate de barco (`[COORD]`), coleta reps (`[COLETA]`) e informa a normalização do rio (`[INFO]`). |
| **`henrique`** | N2 | **Newbie (Novato sem Reputação)** | Morador recém-chegado à Rua Tapajós. Começa com **0 reps** e ingressa na Semana 3 usando `--beg` para publicar uma `[INFO]` sobre um bueiro entupido. Após ser admitido, atua como membro construtivo: durante a Grande Enchente, publica um pedido urgente de socorro (`[COORD] SOS! Família ilhada...`), realiza sua `[COLETA]` diária e informa o desentupimento do bueiro na Semana 12 (`[INFO]`). |
| **`joao`** | N3 | **Troll / Sabotador** | No Dia 0, tenta postar com 0 reps sem `--beg` e é barrado pelo protocolo. Após receber boas-vindas como morador ribeirinho, publica três conteúdos maliciosos: (1) um `[ALERTA]` falso de rompimento de barragem (Semana 6), que nasce apenas `⚪ PENDENTE` por falta de reps; (2) um `[INFO]` conspiratório dizendo que a cidade vai afundar (Semana 6); e (3) uma sabotagem `[COORD]` durante a enchente dizendo falsamente que o abrigo da escola estava lotado e fechado (Semana 9). |
| **`igor`** | N3 | **Pouco Confiável / Precipitado (com Redenção)** | Comportamento instável: na Semana 7, usa `revoke` precipitadamente contra o alerta real do tronco publicado por `marcos`; na Semana 9, publica `[COORD]` prometendo levar lanterna e kit de primeiros socorros para a escola, mas não comparece; na Semana 12, publica `[INFO]` pedindo desculpas e entregando o kit na escola. |
| **`lucia`** | N3 | **Leitora Passiva (Lurker)** | Moradora que acompanha a chain pelo Nó 3 sem publicar mensagens próprias, mas reage com pequenos `likes` e `dislikes` nos momentos decisivos. |

---

## c. Como os autores reagiram com (dis)likes e (un)revokes

A simulação exercita todas as formas de reação e moderação do Freechains v0.20 ao longo dos 3 meses:

### 1. `like <n> author <pub>` (Semeadura de papéis e Avaliação Pós-Emergência)
- **Semeadura inicial (Semanas 1–2)**: `defesa` transfere reputação a `fernando` (`like 22000 author`) e `gisele` (`like 12000 author`), que por sua vez acolhem `eva`, `marcos`, `joao` e `igor`, enquanto `eva` acolhe a vizinha `lucia` (`like 1500 author`).
- **Fase 5 — Avaliação Pós-Emergência (Semana 10 / Dia 70)**: após o encerramento da Grande Enchente, os participantes listados pela aplicação avaliam o desempenho real de cada pessoa:
  - `fernando` recebe likes de `defesa` (`9500`), `eva` (`3500`) e `gisele` (`1200`), reconsolidando seu papel de **`COORDENADOR` (`>= 19.000 reps`)** ao final dos 3 meses (`19.430 reps`).
  - `gisele` recebe likes de `defesa` (`6000`) e `fernando` (`1500`), mantendo-se como **`CONFIRMADOR` (`11.300 reps`)**.
  - `marcos` recebe likes de `lucia` (`400`, grata pelo resgate de barco) e `fernando` (`1500`), subindo para **`CONFIRMADOR` (`10.065 reps`)**.
  - `eva` e `henrique` recebem likes de `1000` pelo alerta rápido e pelo SOS que salvou duas crianças.

### 2. `like <n> action <id>` (Memória institucional, Confirmações e Admissão de `--beg`)
- **Consolidação da memória institucional (Semana 2)**: a `[INFO]` da rota de fuga de `marcos` recebe likes de `fernando`, `eva` e `lucia` (`945 reps` no post), e a `[INFO]` do abrigo de `gisele` recebe like de `fernando` (`450 reps` no post), colocando ambos no topo das sugestões de `alerta.py protocolo --usar-memoria`.
- **Admissão de Newbie via `--beg` (Semana 3)**: o post `--beg` de `henrique` sai de `list begs` e entra no DAG quando `gisele` executa `like 1500 action`, creditando `675 reps` ao post e `675 reps` ao autor `henrique`.
- **Confirmação de alertas, protocolo e memória final (Semanas 4, 8–9 e 13)**: os alertas de `eva` recebem likes junto com os posts `[CONFIRMA]` (o alerta da Grande Enchente termina em 1º lugar no ranking de ações, com `1.080 reps`), assim como o `[PROTOCOLO]`, o SOS de `henrique`, o `[ENCERRA]`, a redenção de `igor` e o post final de memória da enchente.

### 3. `dislike <n> action <id>` e `dislike <n> author <pub>` (Contenção de Trolls e Falhas)
- **Punição aos posts do troll (`joao`)**: o alarme falso da barragem (Semana 6) recebe dislikes de `fernando` (`1000`), `eva` (`800`) e `marcos` (`500`), caindo para **`-2.160 reps`**. O boato conspiratório de `joao` recebe dislikes de `gisele` (`500`) e `lucia` (`200`), ficando com **`-315 reps`**. A sabotagem do abrigo durante a enchente (Semana 9) recebe dislike de `gisele` (`800`), somando-se às revogações.
- **Punição direta aos autores infratores**: na Semana 6, `fernando` aplica `dislike 1000 author` em `joao` por reincidência em alarmes falsos. Na Fase 5 de avaliação pós-emergência (Semana 10), `gisele` aplica `dislike 800 author` em `igor` por prometer o kit de socorro e não aparecer, e `fernando` aplica `dislike 500 action` no post `[COORD]` da promessa não cumprida (`-225 reps`).

### 4. `revoke <n> <id>` e `unrevoke <n> <id>` (Moderação Descentralizada e Reversão)
- **Supressão de alarme falso e sabotagem (`revoke`)**: na Semana 6, `defesa` (`1500`) e `fernando` (`1000`) revogam o falso alerta de rompimento de barragem de `joao`. Na Semana 9, `gisele` (`1000`) e `fernando` (`1500`) revogam a mensagem de sabotagem de `joao` que dizia que o abrigo estava fechado. Em ambos os casos, `get payload` passa a retornar `ERROR : chain get : revoked payload` (estado `🚫 REVOGADO` na UI).
- **Reversão de revogação injusta (`unrevoke --file=...`)**: na Semana 7, `igor` revoga por engano (`revoke 1500`) o `[ALERTA]` real de `marcos` sobre o tronco gigante no rio. Imediatamente, `fernando` (`unrevoke 1500 --file=...`), `eva` (`unrevoke 1000 --file=...`) e `gisele` (`like 1000 action --file=...`) restauram o payload na chain, comprovando que um erro individual de moderação é reversível pelo consenso comunitário.
- **Auto-revogação (Direito ao Esquecimento)**: na Semana 7, `eva` publica por engano seu telefone pessoal e executa `revoke` no próprio post dois minutos depois, removendo definitivamente o payload.

---

## d. Conclusão sobre a simulação

Os resultados obtidos ao final dos 92 dias simulados (`simul.log`) demonstram como o protocolo **Freechains v0.20** sustenta todas as regras de negócio da aplicação de alertas comunitários sem servidor central:

1. **Progressão orgânica de reputação e papéis da aplicação**:
   Ao final do Dia 92, a distribuição de reputação reflete fielmente o comportamento de cada perfil durante os 3 meses:
   | Usuário | Nó | Reputação Final (Dia 92) | Papel Final na Aplicação (`alerta.py`) |
   |---|---|---:|---|
   | **`fernando`** | N1 | **`19.430 reps`** | **`COORDENADOR` (`>= 19.000`)** — liderou confirmações, protocolo e encerramentos |
   | **`gisele`** | N2 | **`11.300 reps`** | **`CONFIRMADOR` (`>= 10.000`)** — gerenciou o abrigo e validou alertas |
   | **`marcos`** | N3 | **`10.065 reps`** | **`CONFIRMADOR` (`>= 10.000`)** — promovido graças às rotas virais e resgates de barco |
   | **`henrique`** | N2 | **`6.525 reps`** | `membro` — entrou com `0 reps` via `--beg` e subiu ajudando na enchente |
   | **`eva`** | N2 | **`3.030 reps`** | `membro` — emitiu os alertas reais e premiou os coordenadores do resgate |
   | **`igor`** | N3 | **`1.985 reps`** | `membro` — penalizado pelo `revoke` errado e ausência na crise, recuperou-se parcialmente na redenção |
   | **`defesa`** | N1 | **`1.000 reps`** | `membro` — pioneira que descentralizou sua reputação inicial para a comunidade |
   | **`joao`** | N3 | **`425 reps`** | `membro` — troll neutralizado por dislikes; seus alertas jamais passaram de `⚪ PENDENTE` antes de serem `🚫 REVOGADOS` |
   | **`lucia`** | N3 | **`50 reps`** | `membro` — leitora passiva que usou seus reps para curtir a rota de fuga, punir boato e agradecer ao barqueiro |

2. **Eficácia da Coleta Diária Condicionada (`[COLETA]`) e Memória Institucional (`[INFO]` -> `[PROTOCOLO]`)**:
   Quem participou ativamente dos alertas válidos pôde acionar a coleta diária de `+1.000 reps` (via consolidação de 24h do Freechains), repondo os custos das ações durante a crise. Além disso, as postagens `[INFO]` de rota de fuga e abrigo publicadas na Semana 2 permaneceram no topo de `reps actions` e foram incorporadas ao `[PROTOCOLO]` da Grande Enchente na Semana 9.
3. **Moderação descentralizada sem ponto único de falha**:
   O sistema bloqueou postagem sem reputação no Dia 0, acolheu um novato legítimo via `--beg` na Semana 3, removeu o payload de alarmes falsos e sabotagens com `revoke` nas Semanas 6 e 9, e reverteu uma censura precipitada com `unrevoke` na Semana 7.
4. **Convergência P2P total entre os 3 nós**:
   Ao término dos 92 dias, os nós `N1`, `N2` e `N3` apresentaram exatamente o mesmo hash `md5sum` para `freechains chain '#alertas-rio-madeira' list order`, comprovando consistência determinística em toda a malha.
