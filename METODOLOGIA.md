# Metodologia do agregador de pesquisas — Senado PB 2026

Este documento descreve o agregador de pesquisas eleitorais para o Senado na
Paraíba (eleição de 4 de outubro de 2026). O agregador transforma pesquisas
publicadas em formatos diferentes numa série diária de intenção de voto, corrige
o viés relativo de cada instituto e projeta a probabilidade de cada candidato
terminar entre os dois mais votados. Numa eleição com duas vagas e dois votos
por eleitor, isso equivale a ser eleito.

A projeção usa as pesquisas publicadas até a véspera da eleição (03/10/2026).
A data de corte é um parâmetro, e a avaliação ex post (seção 10) refaz a
projeção em datas anteriores.

**Como os parâmetros foram escolhidos.** Nenhum parâmetro do modelo foi fixado
por conveniência ou por ajuste ao resultado de 2026:

- a banda do kernel, o encolhimento do efeito de instituto e a data usada no
  eixo do tempo foram escolhidos por validação cruzada (seção 8.1);
- o erro sistemático e a deriva da projeção foram estimados com as eleições
  anteriores para Governo e Senado na Paraíba (seção 8.2);
- a fração de indecisos e o peso dos candidatos sem curva própria vêm das
  próprias pesquisas de 2026 (seções 3.4 e 7.4).

As regras de escolha estão registradas em `programs/00_config.R` e foram
aplicadas antes da comparação com o resultado oficial. As poucas escolhas que
não puderam ser testadas estão listadas na seção 12.

---

## 1. Universo de pesquisas

### 1.1 Registro no TSE

Toda pesquisa eleitoral divulgada precisa ser registrada na Justiça Eleitoral
(Lei nº 9.504/1997, art. 33; Resolução TSE nº 23.600/2019 e alterações
posteriores). O TSE publica, nos dados abertos, a ficha técnica de cada registro:
protocolo, empresa, datas de campo e de divulgação, tamanho da amostra e plano
amostral. Os resultados não são publicados.

A base de partida é o arquivo `pesquisa_eleitoral_2026.zip` do Portal de Dados
Abertos do TSE, filtrado para UF = PB e cargo contendo "Senador" (98 registros).

### 1.2 Abrangência

O registro não tem um campo de abrangência. Ela é inferida por regras sobre o
texto do plano amostral e da lista de municípios
(`programs/functions/tse.R`), em quatro classes:

| Classe | Regra (resumo) |
|---|---|
| `rmjp` | menciona apenas João Pessoa, Bayeux, Santa Rita e Cabedelo |
| `municipal` | "amostra utilizada para o município de…", área de coleta de um só município, lista só de bairros de uma cidade |
| `estadual` | "estado da Paraíba", mesorregiões, regiões imediatas, ou lista com João Pessoa, Campina Grande e cidades do Sertão |
| `indefinida` | nenhuma das anteriores; resolvida à mão em `data/manual/abrangencia_manual.csv`, com justificativa |

Resultado: **55 pesquisas estaduais registradas até 03/10/2026**.

---

## 2. Coleta dos resultados

Como o TSE não publica os percentuais, eles foram coletados de duas formas
independentes e depois conferidos. A regra é: **nenhum número entra sem
fonte**. Pesquisa sem resultado localizado fica marcada como não encontrada e
não entra em nenhum cálculo.

1. **Raspagem automatizada (R).**
   - Os portais de notícia da Paraíba (`data/manual/portais.csv`) são
     consultados pela API REST do WordPress
     (`/wp-json/wp/v2/posts?search=…&after=…&before=…`), por nome de instituto
     e intervalo de datas.
   - Cada matéria é ligada a um protocolo pelo número do registro citado no
     texto. Na falta dele, a ligação é feita pelo instituto e pela data: entre
     o fim do campo e 7 dias depois da divulgação registrada.
   - Uma extração semiautomática por expressões regulares associa nomes de
     candidatos a percentuais e identifica o formato publicado
     (`programs/03_extrai.R`).
   - Todas as requisições ficam em cache.
2. **Coleta independente na web.** Uma segunda coleta, feita por busca na web
   sem acesso à primeira, priorizou o PDF do instituto e, na falta dele, matérias
   de imprensa (`data/manual/agent_collection/`).
3. **Conferência.**
   - As duas coletas foram comparadas candidato a candidato, com tolerância de
     0,15 p.p.
   - Os números publicados só em imagem ou PDF, que a raspagem não lê, passaram
     por uma **releitura cega**: uma terceira leitura das mesmas fontes, sem
     acesso aos valores já coletados (`data/manual/verification/`).
   - As divergências restantes foram resolvidas uma a uma. A decisão e a
     justificativa ficam registradas em `data/manual/decisoes_revisao.R`.

O arquivo final dos números é `data/manual/revisao_resultados.csv`. Só entram
no modelo as linhas com status `conferido` ou `conferido_duplo`.

Até 03/10, das 55 pesquisas estaduais registradas, 38 tiveram resultado
localizado. **35 entram no agregador**: são de 8 institutos, somam 58.273
entrevistas e foram publicadas de 27/01 a 03/10/2026.

### 2.1 Regras de inclusão

Ficam fora do agregador:

- **Pesquisas sem resultado localizado.**
- **Pesquisas que publicaram só o 1º voto.** No 1º voto, o eleitor escolhe
  primeiro o nome mais forte, o que superestima o líder em relação à soma dos
  dois votos. Esse formato não é comparável aos demais.
- **Pesquisas com metodologia não confirmada.** É o caso, por exemplo, da
  Podium de abril, cujo PDF traz outra marca e datas de campo diferentes das do
  registro.
- **Pesquisas que mediram só a região de João Pessoa ou um único município.**
- **Institutos excluídos pela regra de punições** (seção 2.2).

### 2.2 Penalidade e exclusão de institutos

O histórico de punições pela Justiça Eleitoral foi levantado em notícias de
imprensa e está em `data/manual/punicoes_institutos.csv`, com data, UF, tipo e
fonte. A regra (`penalidades_instituto()`, em `programs/functions/pipeline.R`)
usa **só as decisões datadas até o dia do corte**. Assim, a projeção não usa
informação que ainda não existia.

| Situação do instituto até o corte | Penalidade $\pi_i$ |
|---|---|
| multa mantida pela Justiça Eleitoral na PB | excluído |
| suspensão ou proibição de divulgação na PB | 0,75 |
| punição só em outros estados | 0,90 |
| nenhuma punição encontrada | 1,00 |

Não contam:

- registros sem decisão (tipo `outro`);
- punições de empresa homônima cuja identidade não foi confirmada
  (`mesma_empresa = FALSE`). É o caso de um "Instituto Ranking" punido em
  Alagoas.

No corte de 03/10, a regra dá o seguinte resultado:

| $\pi_i$ | Institutos |
|---|---|
| excluído | Veritá (multa mantida pelo TRE-PB em 20/08/2026) |
| 0,75 | ANOVA, Índice Inteligência, SETA, TDL |
| 0,90 | AtlasIntel, Datatrends, Quaest, Real Time Big Data |
| 1,00 | Instituto Ranking e os demais |

Uma pesquisa suspensa individualmente continua no agregador se tiver sido
divulgada. A suspensão é cautelar e não julga o mérito; ela pesa sobre o
instituto por meio da penalidade.

Os valores 0,75 e 0,90 são escolhas, não estimativas (seção 12). Desligar as
penalidades muda a probabilidade de Veneziano de 81,5% para 80,1% (seção 7.5).

### 2.3 Data de cada pesquisa

Cada pesquisa é posicionada no tempo pelo **meio do período de campo**, a data
em que a opinião foi medida. A data de publicação na fonte, alternativa
natural, teve erro de previsão praticamente igual na validação cruzada
(seção 8.1). O meio do campo foi escolhido pela regra do menor erro, por
diferença mínima. O parâmetro `data_pesquisa` aceita `meio`, `fim` ou
`divulgacao`.

O corte de dados é sempre pela **data de publicação**: entra a pesquisa
publicada até o dia do corte.

---

## 3. Medida comum: razão com o candidato de referência

### 3.1 Formatos de publicação

Cada eleitor dá dois votos para o Senado, e os institutos publicam os
resultados de formas diferentes. Sejam $v^{(1)}_{c}$ e $v^{(2)}_{c}$ os
percentuais do candidato $c$ no 1º e no 2º voto:

| Formato | Definição | Soma dos candidatos |
|---|---|---|
| soma | $S_c = v^{(1)}_c + v^{(2)}_c$ | ≈ 200% |
| média | $M_c = S_c / 2$ | ≈ 100% |
| citações | $C_c = S_c / \sum_k S_k$ | 100% (só citações válidas) |
| soma construída | $v^{(1)}_c + v^{(2)}_c$, quando só 1º e 2º voto foram publicados | ≈ 200% |

Uma pesquisa pode publicar mais de um conjunto (cenários com listas de nomes
diferentes, ou formatos diferentes). Nesse caso, a escolha
(`escolher_conjunto()`, em `programs/functions/consolidacao.R`) segue esta
ordem:

1. o conjunto com **mais candidatos**;
2. no empate, a ordem soma, média, citações, soma construída.

### 3.2 Log-razão

Seja $J$ o candidato de referência (João Azevêdo, presente em todas as
pesquisas). Para a pesquisa $p$ e o candidato $c \neq J$:

$$
y_{pc} = \log\frac{x_{pc}}{x_{pJ}},
$$

em que $x$ é o percentual publicado, em qualquer dos formatos da tabela acima.
Soma, média e citações são todas proporcionais a $S_c$, com o mesmo fator para
todos os candidatos de uma pesquisa. Por isso,

$$
\frac{S_c}{S_J} = \frac{M_c}{M_J} = \frac{C_c}{C_J},
$$

e a razão não depende do formato. Brancos, nulos e indecisos saem do cálculo,
o que equivale a distribuí-los na proporção dos votos de cada candidato.

O logaritmo torna a escala simétrica e aditiva:

- um viés multiplicativo de instituto vira um deslocamento constante;
- a volta aos votos válidos é uma transformação logística (seção 6).

É a transformação log-razão aditiva da análise de dados composicionais
(Aitchison, 1986).

Candidatos com 0% numa pesquisa não têm log-razão definida. Essa linha sai do
ajuste daquele candidato; as demais linhas da pesquisa ficam.

Para os gráficos, cada pesquisa também é expressa em **votos válidos como
publicados**, $v_{pc} = x_{pc} / \sum_{k \in L_p} x_{pk}$, em que $L_p$ é a
lista de nomes publicada. Rodadas com poucos nomes inflam todos os candidatos
nessa escala, mas não na razão.

### 3.3 Nomes omitidos

A razão entre dois candidatos só independe dos nomes que o instituto deixou
fora da lista se valer uma hipótese: os eleitores do candidato omitido se
redistribuem entre os demais na proporção dos votos deles. É a independência
de alternativas irrelevantes. Quando o omitido tira votos mais de um candidato
que de outro, a razão muda.

Por isso, o conjunto escolhido é o de mais candidatos (seção 3.1). Mesmo assim,
a hipótese não é testada.

### 3.4 Candidatos com e sem curva própria

Têm curva própria João Azevêdo, Veneziano Vital do Rêgo, Nabor Wanderley,
Marcelo Queiroga, Major Fábio e André Gadelha.

Os quatro restantes (Rosilene Santana, João Batista, Adriano Trajano e Rinaldo
Júnior) aparecem em 13 a 19 pesquisas, quase sempre abaixo de 1,5%. Uma curva
própria, nesse nível, seria dominada pelo arredondamento. Por isso cada um
segue André Gadelha, multiplicado por uma razão constante $f_c$, estimada nas
pesquisas que testaram os dois (`razao_ancora()`):

$$
f_c = \exp\!\left\{\frac{\sum_p \sqrt{n_p}\,\log(x_{pc}/x_{p,\text{André}})}{\sum_p \sqrt{n_p}}\right\}.
$$

Os valores estimados são Rosilene 0,18, João Batista 0,35, Adriano Trajano 0,25
e Rinaldo Júnior 0,18. Um candidato que nunca tenha sido testado junto com André
recebe a mediana das razões dos demais; isso não ocorreu em 2026. Na simulação,
eles acompanham o choque de André, sem choque próprio.

---

## 4. Pesos

Cada pesquisa recebe o peso

$$
w_p = \sqrt{n_p}\;\pi_{i(p)},
$$

em que $n_p$ é o tamanho da amostra e $\pi_i$ é a penalidade do instituto
(seção 2.2).

A raiz de $n$ é usada no lugar de $n$, que seria o inverso da variância
amostral, para limitar o domínio das amostras grandes. O erro total das
pesquisas é bem maior que o erro amostral (Shirani-Mehr et al., 2018) e não cai
com $n$ na mesma velocidade. A ponderação por $\sqrt{n}$ é a usada pelo
FiveThirtyEight (Silver, 2008), na forma $\sqrt{n/600}$; a constante não altera
o resultado.

---

## 5. Tendência: regressão local ponderada

### 5.1 Estimador

Para cada candidato $c$ e cada dia $t_0$, a curva $m_c(t_0)$ é o intercepto de
uma regressão linear local ponderada (Cleveland, 1979; Cleveland e Devlin, 1988;
Fan e Gijbels, 1996):

$$
\big(\hat\alpha, \hat\beta\big) = \arg\min_{\alpha,\beta}
\sum_p K\!\left(\frac{t_p - t_0}{h}\right) w_p
\Big[\tilde y_{pc} - \alpha - \beta\,(t_p - t_0)\Big]^2,
\qquad \hat m_c(t_0) = \hat\alpha.
$$

Aqui $\tilde y_{pc} = y_{pc} - \hat h_{i(p)c}$ é a log-razão corrigida pelo
efeito de instituto (seção 5.3), e o kernel é gaussiano:

$$
K(u) = \exp\!\left(-\tfrac{u^2}{2}\right), \qquad h = 48 \text{ dias}.
$$

O valor de $h$ foi escolhido por validação cruzada (seção 8.1). Com $h = 48$, uma
pesquisa feita 48 dias antes de $t_0$ pesa 61% de uma feita em $t_0$; uma feita
96 dias antes pesa 14%. A largura à meia altura do kernel é de cerca de 113
dias. É uma suavização forte, coerente com o que a validação cruzada mostrou: a
variação entre pesquisas próximas é dominada por ruído, não por mudança de
opinião.

Em forma matricial, com $X_{t_0} = [\mathbf 1,\; t - t_0]$ e
$W_{t_0} = \operatorname{diag}\{K(\cdot)\,w_p\}$,

$$
\hat m_c(t_0) = e_1^\top \big(X_{t_0}^\top W_{t_0} X_{t_0}\big)^{-1} X_{t_0}^\top W_{t_0}\,\tilde y_c
= \sum_p \ell_p(t_0)\,\tilde y_{pc}.
$$

Se houver menos de três pesquisas com peso positivo, ou datas quase iguais, o
estimador cai para a média local ponderada. Com o kernel gaussiano todas as
pesquisas têm peso positivo, e essa regra só seria acionada com menos de três
pesquisas no total.

### 5.2 Erro-padrão

O erro-padrão da curva usa os pesos do suavizador $\ell_p(t_0)$ e os resíduos
$\hat r_{pc} = \tilde y_{pc} - \hat m_c(t_p)$, na forma sanduíche HC0 (White,
1980):

$$
\widehat{\operatorname{ep}}\big(\hat m_c(t_0)\big) = \sqrt{\sum_p \ell_p(t_0)^2\, \hat r_{pc}^{\,2}}.
$$

Esse erro-padrão é otimista, por três razões:

- trata as pesquisas de um mesmo instituto como independentes;
- ignora a incerteza dos efeitos de instituto;
- ignora a incerteza da própria escolha de $h$.

Na projeção, isso é compensado pela calibração. O erro sistemático (seção 8.2)
foi estimado *dado* este erro-padrão. Se o erro-padrão é pequeno demais, a
diferença aparece como erro sistemático maior.

### 5.3 Efeito de instituto (*house effect*)

O viés de cada instituto $i$ para cada candidato $c$ é medido contra o
**consenso dos demais**. O conceito de efeito de instituto vem da literatura de
agregação de pesquisas (Jackman, 2005; Pickup e Johnston, 2008), em que o efeito
costuma ser ancorado no resultado da eleição anterior. Aqui, sem essa âncora, o
efeito é relativo à média dos institutos. O cálculo tem cinco passos:

1. Ajusta-se a curva sem as pesquisas de $i$, $\hat m^{(-i)}_c$.
2. Calcula-se o resíduo médio ponderado de $i$:
   $$
   \bar h_{ic} = \frac{\sum_{p \in i} w_p\,\big[y_{pc} - \hat m^{(-i)}_c(t_p)\big]}{\sum_{p \in i} w_p}.
   $$
3. Encolhe-se o efeito em direção a zero conforme o número $k_i$ de pesquisas
   do instituto:
   $$
   \hat h_{ic} = \frac{k_i}{k_i + \kappa}\,\bar h_{ic}, \qquad \kappa = 2.
   $$
   É o fator de credibilidade de Bühlmann (1967). Ele equivale a uma média a
   posteriori com distribuição a priori centrada em zero e peso de $\kappa$
   pesquisas neutras.
   - Com uma única pesquisa, só 1/3 do desvio é atribuído a viés; com 10
     pesquisas, 83%.
   - O valor de $\kappa$ não é estimado a partir das variâncias entre e dentro
     de institutos, como numa abordagem de Bayes empírico. Ele foi escolhido
     por validação cruzada (seção 8.1).
   - $\kappa = 0$ (sem encolhimento) e $\kappa = \infty$ (sem correção) erram
     mais que $\kappa = 2$.
4. Centraliza-se para que o efeito médio, ponderado pelo peso total de cada
   instituto, seja zero:
   $$
   \hat h_{ic} \leftarrow \hat h_{ic} - \frac{\sum_{i'} W_{i'}\,\hat h_{i'c}}{\sum_{i'} W_{i'}},
   \qquad W_i = \sum_{p \in i} w_p.
   $$
   O encolhimento (passo 3) é aplicado antes desta centralização. Por isso a
   fração efetivamente atribuída ao instituto pode diferir um pouco de
   $k_i/(k_i+\kappa)$.
5. Repete-se com $\tilde y = y - \hat h$, com amortecimento
   ($\hat h \leftarrow 0{,}5\,\hat h^{\text{novo}} + 0{,}5\,\hat h^{\text{anterior}}$)
   para evitar oscilação entre institutos que se corrigem mutuamente. A
   iteração para quando a maior variação, medida depois do amortecimento, fica
   abaixo de $10^{-4}$. Em 2026 isso leva 12 iterações.

Com 8 institutos e 5 candidatos com curva além da referência, são 40 efeitos
estimados com 35 pesquisas. Vários institutos têm 1 a 4 pesquisas, e o
encolhimento é o que impede que esses efeitos absorvam ruído. O efeito é
reportado em % relativo à razão com João, $\exp(\hat h_{ic}) - 1$. Para Nabor,
vai de −22,3% (Índice Inteligência) a +22,8% (SETA).

---

## 6. Volta aos votos válidos

Com $\hat m_J \equiv 0$ e $r_c(t) = \exp\{\hat m_c(t)\}$ (e $r_c = f_c\,r_{\text{André}}$
para os candidatos sem curva), a participação de cada candidato nos votos
válidos é

$$
s_c(t) = \frac{r_c(t)}{\sum_k r_k(t)},
$$

que soma 1 por construção. Os indecisos ficam distribuídos na proporção dos
votos de cada candidato.

---

## 7. Projeção para o dia da eleição

### 7.1 Nível projetado

A projeção mantém o nível do agregador na data da última pesquisa, $T$, sem
prolongar a tendência: $\mu_c = \hat m_c(T)$. Com o eixo no meio do campo,
$T = 02/10/2026$, a $\Delta = 2$ dias da eleição.

### 7.2 Simulação

A eleição é simulada $S = 200\,000$ vezes. Em cada simulação $s$:

$$
\log \tilde r^{(s)}_c = \mu_c + \operatorname{ep}_c\, z^{(s)}_c + \sigma\big(\varepsilon^{(s)}_c - \varepsilon^{(s)}_J\big),
\qquad z, \varepsilon \overset{\text{iid}}{\sim} N(0,1),
\qquad \sigma = \sqrt{\sigma_s^2 + \sigma_d^2\,\Delta},
$$

somando três fontes de incerteza:

| Componente | Valor | Origem |
|---|---|---|
| erro de estimação $\operatorname{ep}_c$ | seção 5.2 | dados de 2026 |
| deriva até a eleição $\sigma_d\sqrt{\Delta}$ | $\sigma_d = 0{,}061$ por raiz de dia | eleições anteriores (seção 8.2) |
| erro sistemático $\sigma_s$ | 0,20 | eleições anteriores (seção 8.2) |

Em 2026, $\sigma = \sqrt{0{,}20^2 + 0{,}061^2 \times 2} = 0{,}218$.

O choque $\varepsilon$ é sorteado de forma independente para cada candidato,
inclusive João. Isso equivale a um erro multiplicativo log-normal sobre a
votação de cada um. Como o choque de João entra em todas as razões, os erros
das log-razões têm correlação 1/2 entre si. Fora isso, o modelo não tem
correlação entre candidatos: não prevê, por exemplo, que dois aliados errem
juntos (seção 11). A seção 8.2 testa duas alternativas para o líder: um choque
próprio maior e um viés com direção. Nenhuma das duas melhorou o ajuste na
véspera.

Os votos válidos simulados são $s^{(s)}_c = \tilde r^{(s)}_c / \sum_k \tilde r^{(s)}_k$.

### 7.3 Probabilidade e faixas

$$
\hat P(\text{eleito}_c) = \frac{1}{S}\sum_{s=1}^{S} \mathbf 1\big\{\operatorname{posto}\big(s^{(s)}_c\big) \le 2\big\},
\qquad
\text{faixa de 80\%} = \big[q_{0{,}10}(s_c),\; q_{0{,}90}(s_c)\big].
$$

Considere dois candidatos, V e N, disputando a 2ª vaga, quando a 1ª está
decidida. Nesse caso, $P(N > V)$ se aproxima de

$$
\Phi\!\left(-\frac{\mu_V - \mu_N}{\sqrt{2\sigma^2 + \operatorname{ep}_V^2 + \operatorname{ep}_N^2}}\right),
$$

porque a diferença dos choques, $\sigma(\varepsilon_V - \varepsilon_N)$, tem
variância $2\sigma^2$. Os testes unitários usam essa aproximação para conferir
a simulação.

### 7.4 Resultado (corte de 03/10/2026)

| Candidato | Projeção (válidos) | Faixa de 80% | P(eleito) |
|---|---|---|---|
| João Azevêdo | 37,6% | 30,1–44,9 | 99,6% |
| Veneziano Vital do Rêgo | 24,2% | 18,5–30,3 | 81,5% |
| Nabor Wanderley | 18,3% | 13,8–23,4 | 18,8% |
| Marcelo Queiroga | 10,7% | 7,8–14,0 | 0,2% |
| Major Fábio | 5,5% | 3,9–7,4 | <0,1% |
| André Gadelha | 1,9% | 1,3–2,6 | <0,1% |
| João Batista / Adriano Trajano / Rosilene Santana / Rinaldo Júnior | 0,7 / 0,5 / 0,3 / 0,3% | — | <0,1% |

### 7.5 Sensibilidade

**Indecisos.** Neste cenário, os indecisos vão todos, divididos igualmente,
para Veneziano e Nabor. A fração de indecisos entre quem não vota branco ou
nulo é a mediana das pesquisas do agregador: $u = 17{,}7\%$, calculada em
`data/processed/indecisos.csv`. Ela é aplicada depois do choque de cada
simulação:

$$
\tilde s_c = (1 - u)\,s_c + \tfrac{u}{2}\,\mathbf 1\{c \in \{V, N\}\}.
$$

A ordem entre Veneziano e Nabor se preserva. A diferença em pontos encolhe
para $(1-u)(s_V - s_N)$. João perde votos e passa a poder ser alcançado.
Resultado: João 87,2%, Veneziano 84,7%, Nabor 28,1%.

**Um parâmetro por vez.** O agregador é reajustado quando o parâmetro afeta a
curva. Os resultados estão em `output/sensibilidade.csv`.

| Variação | João | Veneziano | Nabor |
|---|---|---|---|
| principal | 99,6 | 81,5 | 18,8 |
| $\sigma_s$ no limite inferior do IC de 90% (0,15) | 99,9 | 86,9 | 13,2 |
| $\sigma_s$ no limite superior do IC de 90% (0,27) | 98,1 | 75,3 | 25,6 |
| sem deriva ($\sigma_d = 0$) | 99,7 | 83,6 | 16,6 |
| deriva dobrada ($\sigma_d = 0{,}122$) | 98,6 | 76,9 | 23,8 |
| $\kappa = 0$ (efeito sem encolhimento) | 99,5 | 80,6 | 19,8 |
| $\kappa = \infty$ (sem correção de instituto) | 99,5 | 83,1 | 17,1 |
| $h = 24$ dias | 99,3 | 79,0 | 21,3 |
| $h = 96$ dias | 99,6 | 81,9 | 18,3 |
| sem penalidade de instituto | 99,5 | 80,1 | 20,2 |
| eixo pela data de divulgação | 99,7 | 84,8 | 15,4 |

Veneziano fica entre 75% e 87% em todas as variações, e Nabor entre 13% e 26%.
O que mais pesa é o tamanho do erro sistemático, que é também o parâmetro
estimado com menos dados (8 disputas).

---

## 8. Escolha dos parâmetros

Gerado por `programs/calibration/`; relatório completo em
`output/calibracao.md`.

### 8.1 Validação cruzada: banda, $\kappa$ e eixo de data

Para cada combinação da grade, cada pesquisa $p$ é prevista sem ela. A
previsão é a curva no dia da pesquisa mais o efeito do seu instituto:

$$
\hat y_{pc} = \hat m^{(-p)}_c(t_p) + \hat h^{(-p)}_{i(p)c}.
$$

A grade (`programs/calibration/c05_validacao_cruzada.R`) é:

- $h \in \{12, 16, 24, 32, 48, 64, 96, 128\}$ dias;
- $\kappa \in \{0;\,0{,}5;\,1;\,2;\,4;\,\infty\}$;
- eixo de data: meio do campo ou divulgação.

Há dois critérios:

- **Origem móvel** (critério principal). O ajuste usa só as pesquisas
  publicadas antes de $p$ e, depois da última delas, mantém o nível em vez de
  prolongar a tendência. É exatamente o uso na projeção, feita na ponta da
  série (Tashman, 2000).
- **Deixar uma de fora** (*leave-one-out*, conferência). O ajuste usa todas as
  outras pesquisas (Arlot e Celisse, 2010).

O erro é padronizado pela variância amostral aproximada da log-razão,

$$
z^2_{pc} = \frac{(y_{pc} - \hat y_{pc})^2}{v_{pc}}, \qquad
v_{pc} = \frac{1}{n_p\,x_{pc}/100} + \frac{1}{n_p\,x_{pJ}/100},
$$

para que pesquisas pequenas e candidatos pequenos não dominem a soma. Entram o
Senado 2026, com pesquisas até o corte, e as 8 disputas anteriores da seção
8.2: 282 previsões na origem móvel, 361 na de deixar uma de fora.

Resultados com o eixo no meio do campo, na origem móvel:

| $h$ | $\kappa=0$ | 0,5 | 1 | **2** | 4 | $\infty$ |
|---|---|---|---|---|---|---|
| 12 | 25,9 | 18,0 | 15,4 | 13,3 | 12,4 | 13,9 |
| 24 | 13,7 | 11,4 | 10,8 | 10,7 | 11,0 | 13,5 |
| 32 | 13,6 | 11,3 | 10,8 | 10,6 | 10,9 | 13,6 |
| **48** | 13,3 | 11,1 | 10,6 | **10,4** | 10,7 | 13,4 |
| 64 | 13,3 | 11,2 | 10,6 | 10,4 | 10,8 | 13,4 |
| 96 | 13,4 | 11,3 | 10,8 | 10,6 | 10,9 | 13,5 |

O que a validação mostra:

- **O mínimo está em $h = 48$, $\kappa = 2$, meio do campo.** O critério de
  deixar uma de fora concorda: mínimo em $h = 64$, $\kappa = 2$, com diferença
  desprezível.
- **A superfície é plana entre 32 e 96 dias.** As disputas puxam em direções
  opostas. Governador 2018, com forte crescimento do vencedor na reta final,
  prefere bandas curtas; as demais preferem bandas longas.
- **A correção de instituto se justifica.** $\kappa = \infty$, que é não
  corrigir, erra 29% mais.
- **O encolhimento também.** $\kappa = 0$, que é corrigir sem encolher, erra 28%
  mais.
- **O ruído entre pesquisas é grande.** $z^2 \approx 10$ indica que a variância
  dos erros é cerca de 10 vezes a amostral, ou seja, o erro típico entre
  pesquisas é cerca de 3 vezes o erro amostral. Isso é coerente com
  Shirani-Mehr et al. (2018).

### 8.2 Eleições anteriores: erro sistemático e deriva

**Dados.** As pesquisas estaduais para Governo (1º e 2º turnos) e Senado na
Paraíba em 2014, 2018 e 2022 foram listadas nas fichas do TSE: campo nos 90
dias antes do 1º turno, ou entre os turnos. A coleta usou o mesmo método de
2026, com duas coletas independentes:

- uma podia usar a Wikipedia como índice, mas confirmava cada número na fonte
  primária;
- a outra era cega e não usava agregadores.

Das pesquisas achadas pelas duas coletas, todas foram conferidas; as
divergências eram candidatos abaixo de 1% ou erros de digitação da fonte. As
achadas por uma só passaram por releitura cega. Ficaram fora:

- uma pesquisa de intenção espontânea;
- uma postada só no dia da eleição;
- uma divulgada apenas depois da eleição.

As decisões estão em `data/manual/calibration/decisoes_historicas.csv`. A base
final tem **82 pesquisas em 8 disputas**.

Duas regras definem o que entra na comparação:

- **Referência.** Em cada disputa, a referência é o líder nas pesquisas e só
  têm curva os candidatos com média de pelo menos 3% nas pesquisas. Ambas as
  escolhas são feitas sem olhar o resultado.
- **Votos anulados.** Candidatos com votos anulados ficam fora, porque não têm
  razão no resultado. É o caso de Ricardo Coutinho, no Senado 2022. A razão
  entre os demais não muda.

O resultado é a votação oficial em votos válidos
(`votacao_candidato_munzona_<ano>.zip`).

**Modelo.** O agregador, com os parâmetros da seção 8.1, roda em cada disputa
com as pesquisas publicadas até $h$ dias antes da eleição,
$h \in \{0, 7, 14, 21, 28\}$. O erro de cada candidato, na escala log-razão
contra a referência, é

$$
e_c = \log\frac{R_c}{R_{\text{ref}}} - \hat\mu_c,
$$

em que $R$ é o resultado oficial. Para o vetor de erros de uma disputa, o
modelo é

$$
\mathbf e \sim N\!\left(b\,\mathbf 1,\;\operatorname{diag}(\operatorname{ep}_c^2 + s^2) + t^2\,\mathbf 1\mathbf 1^\top\right).
$$

- Com choques independentes e iguais por candidato, que é o modelo da seção
  7.2, $t = s$ e $b = 0$.
- $t > s$ indica que o líder erra mais que os demais.
- $b \neq 0$ indica que o erro do líder tem direção.

Os parâmetros são estimados por máxima verossimilhança, um horizonte por vez,
porque os horizontes reaproveitam as mesmas pesquisas. Os modelos são comparados
pelo AIC (Akaike, 1974).

**Resultados na véspera** (8 disputas, em média 2,4 dias entre a última
pesquisa e a eleição):

| Modelo | $s$ | IC 90% | $t$ | $b$ (ep) | AIC |
|---|---|---|---|---|---|
| **choques independentes** | **0,223** | 0,168–0,296 | | | **8,8** |
| + choque do líder | 0,209 | | 0,251 | | 10,6 |
| + viés do líder | 0,219 | | | 0,076 (0,096) | 10,2 |
| + ambos | 0,210 | | 0,238 | 0,074 (0,100) | 12,1 |

O modelo de choques independentes tem o menor AIC, e a regra registrada o
adota. A 2–4 semanas da eleição, o choque do líder estimado é maior ($t$ de
0,36 a 0,63 contra $s$ de 0,24 a 0,31), mas não melhora o AIC de forma
consistente. Com 5 a 8 disputas, não há evidência suficiente para o termo
extra.

**Deriva.** O erro total cresce com a distância até a eleição: $s$ vai de 0,22
na véspera a 0,43 a quatro semanas. A regressão de $s^2$ nos dias médios de
cada horizonte,

$$
s_h^2 = \sigma_s^2 + \sigma_d^2\,\bar\Delta_h,
$$

dá $\sigma_d = 0{,}061$ por raiz de dia. O erro sistemático propriamente dito,
descontada a deriva embutida na véspera, é

$$
\sigma_s = \sqrt{0{,}223^2 - 0{,}061^2 \times 2{,}4} = 0{,}20.
$$

Na escala de votos, $\sigma = 0{,}22$ numa log-razão de candidato com cerca de
24% dos válidos corresponde a um desvio-padrão de aproximadamente ±5 p.p. Esse
é o erro típico do agregador na véspera, nas eleições anteriores da Paraíba.

---

## 9. Testes

`tests/testthat/test_modelo.R` verifica quatro coisas:

- a regressão local reproduz uma reta conhecida;
- o efeito de instituto recupera um viés plantado em dados simulados;
- os votos válidos somam 1;
- a simulação reproduz a probabilidade analítica da seção 7.3.

---

## 10. Avaliação ex post

A comparação com o resultado oficial de 2026 está em
`output/avaliacao_ex_post.md`, gerada por `programs/08_avaliacao.R`. Ela foi
feita depois de todos os parâmetros fixados e não alterou nenhum deles.

| Candidato | Projeção | Faixa de 80% | Resultado | Erro (p.p.) |
|---|---|---|---|---|
| João Azevêdo | 37,6 | 30,1–44,9 | 32,5 | −5,1 |
| Veneziano Vital do Rêgo | 24,2 | 18,5–30,3 | 22,8 | −1,4 |
| Nabor Wanderley | 18,3 | 13,8–23,4 | 20,9 | +2,6 |
| Marcelo Queiroga | 10,7 | 7,8–14,0 | 12,5 | +1,8 |
| Major Fábio | 5,5 | 3,9–7,4 | 7,7 | +2,2 |
| André Gadelha | 1,9 | 1,3–2,6 | 2,8 | +0,9 |

Os dois eleitos (João, 99,6%; Veneziano, 81,5%) eram os de maior
probabilidade. Dos 6 candidatos com curva, 4 ficaram dentro da faixa de 80%;
Major Fábio e André Gadelha ficaram pouco acima. O erro absoluto médio foi de
2,4 p.p.

O erro teve o padrão de líder superestimado: João abaixo, todos os demais acima.
É o padrão que o termo de choque do líder ($t$, seção 8.2) captaria. Nas
eleições anteriores, ele não teve suporte na véspera, só a 2–4 semanas. Uma
eleição a mais não muda essa conclusão sozinha, mas é o primeiro candidato a
revisão quando houver mais disputas para calibrar.

Refeita em cortes quinzenais, a projeção já apontava João e Veneziano como os
mais prováveis desde junho:

- a probabilidade de Veneziano ficou entre 70% e 84%;
- o erro absoluto médio caiu de 6,5 p.p. em junho para 2,4 p.p. na véspera.

---

## 11. Limitações

- **Ancoragem no consenso.** A correção de instituto retira o viés relativo
  entre institutos, mas não o viés comum a todos. Se as pesquisas erram juntas,
  o agregador erra junto. Esse erro comum é o que o erro sistemático
  $\sigma_s$ representa, com a estrutura da seção 7.2.
- **Correlação entre candidatos.** O choque do líder entra em todas as razões,
  mas não há correlação própria entre candidatos. Coligações (João e Nabor;
  Veneziano e André Gadelha) e voto casado não são modelados. O teste de um
  choque extra do líder não teve suporte suficiente com 8 disputas.
- **Calibração com poucas eleições.** O erro sistemático vem de 8 disputas, com
  intervalo de 90% de 0,17 a 0,30 para o erro na véspera. Nenhuma delas é de
  Senado com duas vagas e cinco candidatos competitivos, como em 2026. Em 2018
  havia duas vagas, mas outra configuração.
- **Institutos diferentes.** Quase nenhum dos institutos de 2026 pesquisou o
  estado em 2014–2022. O erro histórico mede o agregador, não estes institutos.
- **Penalidades.** O histórico de punições vem de notícias de imprensa, não de
  consulta direta aos processos. Os valores 0,75 e 0,90 são escolhas.
- **Cobertura da coleta.** 17 das 55 pesquisas registradas não tiveram
  resultado localizado em texto, por terem números só em vídeo ou por não terem
  sido divulgadas.
- **Nomes omitidos e indecisos.** A razão supõe que eleitores de nomes omitidos
  e indecisos se distribuem na proporção dos votos (seções 3.2 e 3.3).

---

## 12. Parâmetros

Todos em `programs/00_config.R`.

| Parâmetro | Valor | Origem |
|---|---|---|
| `corte` | 03/10/2026 | véspera da eleição |
| `referencia` | João Azevêdo | presente em todas as pesquisas |
| `data_pesquisa` | meio do campo | validação cruzada (8.1) |
| `kernel`, `banda_dias` | gaussiano, 48 dias | validação cruzada (8.1) |
| `kappa` | 2 | validação cruzada (8.1) |
| peso | $\sqrt{n} \times \pi_i$ | escolha (seção 4) |
| `penalidade` | excluído / 0,75 / 0,90 / 1 | regra datada (2.2); valores por escolha |
| `sigma_sistematico` | 0,20 | eleições anteriores (8.2) |
| `sigma_deriva_dia` | 0,061 | eleições anteriores (8.2) |
| candidatos sem curva | razão para André estimada | pesquisas de 2026 (3.4) |
| indecisos (sensibilidade) | 17,7% | mediana das pesquisas de 2026 (7.5) |
| `n_sims` | 200.000 | erro de Monte Carlo < 0,1 p.p. nas probabilidades |
| `prob_faixa` | 10% e 90% | faixa de 80% |

As escolhas não testadas são o peso $\sqrt{n}$, os valores das penalidades e o
nível da faixa. O efeito das duas primeiras aparece na seção 7.5.

---

## Referências

Aitchison, J. (1986). *The Statistical Analysis of Compositional Data*.
London: Chapman & Hall.

Akaike, H. (1974). A new look at the statistical model identification. *IEEE
Transactions on Automatic Control*, 19(6), 716–723.

Arlot, S., & Celisse, A. (2010). A survey of cross-validation procedures for
model selection. *Statistics Surveys*, 4, 40–79.

Brasil. Lei nº 9.504, de 30 de setembro de 1997. Estabelece normas para as
eleições (art. 33: registro de pesquisas eleitorais).

Bühlmann, H. (1967). Experience rating and credibility. *ASTIN Bulletin*, 4(3),
199–207.

Cleveland, W. S. (1979). Robust locally weighted regression and smoothing
scatterplots. *Journal of the American Statistical Association*, 74(368),
829–836.

Cleveland, W. S., & Devlin, S. J. (1988). Locally weighted regression: an
approach to regression analysis by local fitting. *Journal of the American
Statistical Association*, 83(403), 596–610.

Fan, J., & Gijbels, I. (1996). *Local Polynomial Modelling and Its
Applications*. London: Chapman & Hall.

Jackman, S. (2005). Pooling the polls over an election campaign. *Australian
Journal of Political Science*, 40(4), 499–517.

Pickup, M., & Johnston, R. (2008). Campaign trial heats as election forecasts:
measurement error and bias in 2004 presidential campaign polls. *International
Journal of Forecasting*, 24(2), 272–284.

Shirani-Mehr, H., Rothschild, D., Goel, S., & Gelman, A. (2018). Disentangling
bias and variance in election polls. *Journal of the American Statistical
Association*, 113(522), 607–614.

Silver, N. (2008). Polls now weighted by sample size. *FiveThirtyEight*.

Tashman, L. J. (2000). Out-of-sample tests of forecasting accuracy: an analysis
and review. *International Journal of Forecasting*, 16(4), 437–450.

Tribunal Superior Eleitoral. Resolução nº 23.600, de 12 de dezembro de 2019, e
alterações posteriores. Dispõe sobre pesquisas eleitorais.

Tribunal Superior Eleitoral. Portal de Dados Abertos: Pesquisas eleitorais
(2014, 2018, 2022, 2026), Candidatos 2026 e Votação nominal por município e
zona (2014, 2018, 2022, 2026).

White, H. (1980). A heteroskedasticity-consistent covariance matrix estimator
and a direct test for heteroskedasticity. *Econometrica*, 48(4), 817–838.
