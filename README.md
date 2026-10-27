# Simulação de 3 Meses: Sistema Comunitário de Alerta e Resposta a Emergências (Freechains v0.20)

Este repositório contém a simulação reproduzível de **3 meses (92 dias / 13 semanas)** da cadeia pública `#alertas-rio-madeira` utilizando o **Freechains v0.20**, com passagem de tempo controlada via `--now=<secs>`, **3 nós P2P** independentes e **9 usuários** com diferentes perfis de atividade e confiabilidade.

A simulação foi projetada em alinhamento direto com a aplicação final da disciplina (**Pergunta #5**): um **Sistema Comunitário de Alerta e Resposta a Emergências** para comunidades ribeirinhas sujeitas a enchentes súbitas.

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

Em comunidades ribeirinhas (como ao longo do Rio Madeira), enchentes súbitas frequentemente comprometem a infraestrutura de internet centralizada exatamente quando a comunicação é mais crítica. Ao mesmo tempo, grupos de mensagens tradicionais sofrem com três problemas graves durante crises:
1. **Desinformação e pânico**: boatos sobre rompimento de barragens ou abrigos supostamente lotados se espalham rapidamente sem possibilidade de verificação ou contenção descentralizada.
2. **Falta de priorização por confiança**: alertas urgentes de moradores experientes na beira do rio se perdem em meio a mensagens triviais ou alarmes falsos de desconhecidos/trolls.
3. **Perda de memória operacional**: rotas de evacuação seguras e locais de abrigo que funcionaram em cheias anteriores não ficam consolidados de forma estruturada para acionamento imediato.

### Intenção da aplicação (Pergunta #5)

A aplicação atua como uma **camada de interface e coordenação sobre o protocolo Freechains v0.20**, sem alterar nenhuma regra do protocolo subjacente. Ela lê o grafo acíclico dirigido (DAG), a reputação dos autores (`reps author`), a reputação das ações (`reps action`) e a lista de revogações (`list revokes`) para estruturar a resposta comunitária em **5 fases**:

| Fase da Emergência | Mecanismo no Freechains v0.20 | Leitura e Decisão da Aplicação |
|---|---|---|
| **1. Emissão do Alerta** | `chain post` (ou `--beg` para novatos sem reps) | Lê `reps author`: se o autor possui alta reputação, exibe como **ALERTA ATIVO**; caso contrário, nasce como **PENDENTE** aguardando verificação. |
| **2. Confirmação** | Posts de confirmação no DAG + `chain like <n> action <id>` | Promove o alerta para **CONFIRMADO** quando recebe confirmações/likes de membros confiáveis; derruba fraudes com `dislike` e `revoke`. |
| **3. Protocolo de Resposta** | `chain post` por coordenador + consulta a posts antigos consolidados | Recupera da **memória institucional** (posts antigos com alto `reps action`) as rotas de fuga e abrigos validados semanas antes. |
| **4. Coordenação em Campo** | `chain post` + `like` / `--beg` + `revoke` contra sabotagem | Organiza resgates de barco, vagas em abrigos e pedidos de SOS (inclusive de novatos via `--beg`), filtrando sabotagens de trolls. |
| **5. Encerramento e Avaliação** | `chain like/dislike <n> author <pub>` | Após o post de encerramento, os moradores avaliam diretamente as **pessoas** que atuaram na emergência, atualizando a reputação para crises futuras. |

### Topologia de nós e distribuição de usuários

A simulação instancia **3 nós independentes** (`--root` distintos, cada um servindo via `freechains daemon start` em sua própria porta local) que sincronizam em malha (`chain sync recv`) ao longo dos 92 dias, evitando *hard forks* (que no v0.20 ocorrem se ramos divergirem por mais de 7 dias ou 100 ações):

| Nó | Localização na Comunidade | Porta | Usuários Alocados |
|---|---|---|---|
| **N1** | Sede da Defesa Civil (Centro) | `8401` | `defesa` (pioneira), `fernando` |
| **N2** | Bairro Rua Amazonas | `8402` | `eva`, `gisele`, `henrique` |
| **N3** | Comunidade Ribeirinha (Porto) | `8403` | `marcos`, `joao`, `igor`, `lucia` |

---

## b. Natureza das mensagens postadas por cada tipo de autor

Os **9 usuários** foram modelados com perfis distintos de atividade, comportamento social e qualidade de postagens para exercitar todos os mecanismos do Freechains v0.20:

| Usuário | Nó | Perfil de Usuário | Natureza das Mensagens Publicadas |
|---|---|---|---|
| **`defesa`** | N1 | **Pioneira Institucional / Moderadora** | Publica o post inaugural com as regras da cadeia (`[REGRAS]`). Posta pouco conteúdo próprio, atuando principalmente na semeadura inicial de reputação, validação de protocolos oficiais e revogação de alarmes falsos graves. |
| **`fernando`** | N1 | **Coordenador Ativo / Voluntário** | Enfermeiro voluntário muito ativo. Publica confirmações presenciais em campo, emite o **Protocolo de Resposta** durante a grande enchente, publica o boletim de **Encerramento** e registra a **Memória Institucional** (lições aprendidas). |
| **`eva`** | N2 | **Emissora Confiável (Líder de Rua)** | Moradora atenta na beira do rio. Publica medições neutras de rotina (*"Marca na ponte: 4,2 m"*), emite o primeiro alerta menor de chuva forte (Semana 4), emite o **alerta crítico da Grande Enchente** (Semana 9) e faz uma postagem pessoal com seu telefone da qual se arrepende em seguida (exercitando auto-revogação). |
| **`gisele`** | N2 | **Confirmadora / Gestora de Abrigo** | Diretora da Escola Municipal. Publica informações de utilidade pública (cadastro da escola como abrigo para 50 pessoas, chegada de doações de colchões, status de ocupação durante a cheia) e confirmações de nível de água na Rua Amazonas. |
| **`marcos`** | N3 | **Autor de Conteúdo "Viral" (Barqueiro)** | Conhecedor profundo do rio. Publica informações de altíssimo valor comunitário que viralizam em curtidas: a **Rota de Fuga segura** até o Morro do Cruzeiro, o alerta real de um tronco gigante descendo o rio, a mobilização de barco de resgate e o aviso de normalização do nível do rio. |
| **`henrique`** | N2 | **Newbie (Novato sem Reputação)** | Morador recém-chegado à Rua Tapajós. Começa com **0 reps** e utiliza `--beg` na Semana 3 para relatar um bueiro entupido. Depois de acolhido pela comunidade, participa como membro regular, emitindo um pedido urgente de **SOS** para uma família ilhada na Semana 9 e informando a limpeza do bueiro na Semana 12. |
| **`joao`** | N3 | **Troll / Sabotador** | Tenta postar sem reputação no Dia 0 (e é bloqueado pelo protocolo). Após receber boas-vindas de boa-fé como morador, passa a publicar **alarmes falsos de pânico** (*"[URGENTE] BARRAGEM ROMPEU!!!"*), **boatos conspiratórios** (*"Prefeitura esconde que a cidade vai afundar"*) e **sabotagem direta** durante a enchente (*"Abrigo da escola está cheio, não venham!"*). |
| **`igor`** | N3 | **Pouco Confiável / Precipitado (com Redenção)** | Usuário errático: na Semana 7, revoga precipitadamente um alerta real de `marcos`; na Semana 9, publica uma promessa de ajuda (*"Tenho lanterna e kit... Indo para a escola"*) mas não comparece; na Semana 12, publica um pedido de desculpas e entrega o kit na escola. |
| **`lucia`** | N3 | **Leitora Passiva (Lurker)** | Moradora que não publica textos próprios na cadeia, mas acompanha os alertas pelo Nó 3 e participa pontualmente com pequenos `likes` e `dislikes` em conteúdos e autores que impactam sua segurança. |

---

## c. Como os autores reagiram com (dis)likes e (un)revokes

Durante os 3 meses simulados, a comunidade utilizou todas as primitivas de avaliação e moderação do Freechains v0.20:

### 1. `like <n> author <pub>` (Avaliação positiva de pessoas)
- **Semeadura de confiança (Semanas 1–2)**: `defesa` (pioneira) distribuiu reputação inicial para lideranças conhecidas no mundo real (`fernando`, `eva`, `gisele`, `marcos`). Em seguida, `fernando` e `eva` acolheram outros moradores (`joao`, `igor`, `lucia`), demonstrando a entrada descentralizada (*web of trust*).
- **Avaliação pós-emergência (Semana 10 — Fase 5)**: após o encerramento da enchente, moradores avaliaram diretamente quem trabalhou no resgate: `eva` e `gisele` deram likes ao autor `fernando` (coordenação); `lucia` e `fernando` premiaram `marcos` (resgate de barco); `defesa` premiou `gisele` (gestão do abrigo); e `fernando` premiou `henrique` (aviso que salvou família ilhada).

### 2. `like <n> action <id>` (Validação de postagens e admissão de `--beg`)
- **Conteúdo viral e memória (Semana 2)**: o post de `marcos` sobre a rota de fuga recebeu múltiplos likes (`fernando`, `eva`, `lucia`) e o cadastro do abrigo de `gisele` recebeu like de `defesa`, destacando ambos no ranking de `reps actions` (945 e 450 reps respectivamente).
- **Admissão de Newbie via `--beg` (Semana 3)**: quando `henrique` postou com `--beg` (0 reps), o post ficou retido em `list begs`. O `like 1500 action` de `gisele` admitiu automaticamente a mensagem no DAG e transferiu metade dos reps (menos a taxa de queima de 10%) para `henrique`, tornando-o membro ativo.
- **Confirmação de alertas e protocolo (Semanas 4, 8–9 e 13)**: os alertas reais de `eva`, o protocolo de `fernando`, o SOS de `henrique` e o relatório final de lições aprendidas receberam likes de confirmação.

### 3. `dislike <n> action <id>` e `dislike <n> author <pub>` (Punição a spammers e infratores)
- **Combate a alarmes falsos e boatos (Semanas 5–6 e 9)**: o alarme falso da barragem (`joao`) recebeu dislikes imediatos de `fernando`, `eva` e `marcos` (terminando com `-2385` reps). O segundo boato de `joao` recebeu dislikes de `gisele` e `lucia` (`-315` reps). Na enchente, a sabotagem de `joao` sobre o abrigo recebeu dislike de `gisele` (`-1485` reps).
- **Punição direta aos autores (Semanas 6 e 10)**: diante da reincidência de `joao`, `defesa` aplicou `dislike 1000 author` diretamente na chave pública do troll. Na avaliação pós-emergência (Semana 10), `gisele` aplicou `dislike 800 author` em `igor` por prometer ajuda e não aparecer, enquanto `fernando` deu dislike na postagem da promessa não cumprida (`-225` reps).

### 4. `revoke <n> <id>` e `unrevoke <n> <id>` (Moderação de conteúdo e reversão de erros)
- **Remoção de desinformação perigosa (`revoke`)**: nas Semanas 5 e 9, `defesa`, `fernando` e `gisele` usaram `revoke` contra o alarme falso de rompimento de barragem e contra a sabotagem do abrigo. O payload dessas mensagens deixou de ser acessível via `get payload` (`ERROR : chain get : revoked payload`), embora seus metadados permaneçam auditáveis no DAG (`~id~`).
- **Correção de moderação injusta (`unrevoke`)**: na Semana 7, `igor` revogou por engano o aviso real de `marcos` sobre um tronco perigoso no rio (`revoke 1500`). Após verificarem que o perigo era real, `fernando` e `eva` executaram `unrevoke` (fornecendo `--file` com o payload original) e `defesa` deu um `like`, superando o peso da revogação e restaurando integralmente a visibilidade do alerta para todos os nós.
- **Auto-revogação / Direito ao esquecimento**: na Semana 7, `eva` publicou seu número de telefone pessoal por engano e, dois minutos depois, executou `revoke` no próprio post — no Freechains v0.20, a revogação pelo próprio autor é definitiva e remove o payload imediatamente.

---

## d. Conclusão sobre a simulação

A execução completa de `simul.sh` ao longo dos 92 dias simulados comprova na prática as propriedades fundamentais do Freechains v0.20 aplicadas ao cenário de resposta a emergências:

1. **Resistência a Sybil sem autoridade central**: no Dia 0, a tentativa de postagem de uma chave recém-criada (`joao`) sem reputação foi bloqueada pelo protocolo (`insufficient reputation`). Ao mesmo tempo, um morador legítimo sem reputação (`henrique`) conseguiu ingressar sem burocracia utilizando `--beg`, bastando que qualquer membro com reputação (`gisele`) curtisse sua contribuição útil.
2. **Alinhamento entre reputação final e mérito comunitário**: o placar final no Dia 92 reflete com precisão o histórico de contribuições de cada perfil:
   - Os membros construtivos lideram o ranking: **`marcos` (9.930 reps)**, **`eva` (7.885 reps)**, **`gisele` (6.550 reps)**, **`fernando` (5.425 reps)** e o ex-newbie **`henrique` (5.345 reps)**.
   - A pioneira **`defesa` (500 reps)** cumpriu seu papel descentralizador, transferindo quase toda sua carga inicial para a comunidade ativa.
   - O membro relapso **`igor` (2.300 reps)** perdeu parte relevante de sua reputação pelas falhas, e o troll **`joao` (615 reps)** terminou isolado na base entre os usuários ativos, com seus alertas falsos neutralizados em `-2.385` e `-1.485` reps.
3. **Moderação resiliente e reversível**: a comunidade conseguiu tanto suprimir rapidamente mensagens que colocavam vidas em risco (`revoke` nos boatos de `joao`) quanto reverter uma censura indevida (`unrevoke` no alerta do tronco de `marcos`), além de garantir o direito ao esquecimento imediato na auto-revogação de `eva`.
4. **Convergência P2P determinística**: mesmo com 9 usuários operando concorrentemente em 3 nós distintos (`N1`, `N2`, `N3`), a sincronização periódica garantiu que os 3 nós chegassem ao Dia 92 exatamente com a mesma ordem de consenso (`md5sum` idêntico em `chain list order`).
