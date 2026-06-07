# “The Census of the Saved”: Religious Territories and Bolsonarist Hegemony in Brazil
## Citação
Se este modelo ou os dados tratados aqui dispostos forem úteis para a sua pesquisa, por favor, cite o artigo correspondente:
> CASTRO, Hernany; GRACINO JUNIOR, Paulo; SILVA, Mayra Goulart da. *“The Census of the Saved”: Religious Territories and Bolsonarist Hegemony in Brazil*. [Brasília: 2026].

## Repositório de Replicação Estatística

Este repositório contém o pipeline automatizado em R e a documentação metodológica para a replicação integral dos dados, tabelas e modelos estatísticos apresentados no artigo **“The Census of the Saved”: Religious Territories and Bolsonarist Hegemony in Brazil** (em português: *“O Censo dos Salvos”: Territórios Religiosos e Hegemonia Bolsonarista no Brasil*).

O estudo reinterpreta a arena político-religiosa brasileira a partir do quadro teórico pós-estruturalista de Laclau e Mouffe, articulando dados demográficos do Censo IBGE e resultados eleitorais oficiais do Tribunal Superior Eleitoral (TSE) referentes ao pleito presidencial de 2022.

---

## Estrutura do Modelo e Pipeline

O script `censo_salvos.R` executa uma abordagem metodológica integrada em três estágios coordenados através do ecossistema `tidymodels`:

1. **Análise de Componentes Principais (PCA):** Redução de dimensionalidade sobre as matrizes confessionais e proxies socioeconômicas escalonadas por município, mapeando as superfícies de inscrição discursiva e os eixos de antagonismo.
2. **Modelagem de Aprendizado de Máquina (K-Means & Random Forest):** Clusterização não supervisionada para a criação de uma tipologia territorial de fricção religiosa e validação preditiva não linear da variância do voto.
3. **Regressão Linear Múltipla (OLS):** Isolamento dos efeitos diretos e condicionais das variáveis confessionais e de controle sobre a fronteira de antagonismo político líquido ($Bolsonaro\% - Lula\%$).

---

## Matriz de Outputs Oficiais (Logs do Console)

Para fins de reprodutibilidade estrita, os modelos gerados pelo script local devem convergir exatamente para os parâmetros oficiais descritos abaixo:

### 1. Autovalores e Variância Explicada da PCA (Critério de Guttman-Kaiser)
Extraídos via decomposição espectral nativa (`factoextra::get_eigenvalue`), estruturados em ordem estritamente decrescente de variância:

| Dimensão | Autovalor (*Eigenvalue*) | % da Variância | % Acumulada | Perfil Teórico do Vetor |
| :---: | :---: | :---: | :---: | :--- |
| **PC1** | 2,9648 | 37,06% | 37,06% | Clivagem Cristã Majoritária e Renda |
| **PC2** | 1,1339 | 14,17% | 51,23% | Pluralismo Contra-Hegemônico (Minorias) |
| **PC3** | 1,0011 | 12,51% | 63,75% | Vetor de Desinstitucionalização Secular |
| **PC4** | 0,9952 | 12,44% | 76,18% | Representação Política Corporativa (FPE) |

### 2. Sumário Estatístico da Regressão Linear Múltipla OLS (`modelo_religioes`)
* **Variável Dependente:** `apoio_presid` (Antagonismo Líquido no 2º Turno; Escala de -1 a +1)
* **Ajuste Global:** $R^2$ Múltiplo = 0,5849 | **$R^2$ Ajustado = 0,5844**
* **Significância:** Estatística $F = 1120$ sobre 7 e 5562 DF ($p\text{-valor} < 2,2 \times 10^{-16}$)

| Variável Preditora | Coeficiente (*Estimate*) | Erro Padrão (*Std. Error*) | Estatística $t$ | Pr(>\|t\|) |
| :--- | :---: | :---: | :---: | :---: |
| **(Intercepto)** | -1,1430 | 0,0638 | -17,896 | $< 2,2 \times 10^{-16}$ *** |
| `prop_catolicos` | -0,5789 | 0,0685 | -8,444 | $< 2,2 \times 10^{-16}$ *** |
| `prop_evangelicos` | +0,7510 | 0,0677 | 11,091 | $< 2,2 \times 10^{-16}$ *** |
| `prop_espirita` | -1,7590 | 0,2824 | -6,229 | $5,03 \times 10^{-10}$ *** |
| `prop_afro` | -3,6330 | 0,5202 | -6,983 | $3,22 \times 10^{-12}$ *** |
| `prop_sem_religiao` | -0,2170 | 0,1597 | -1,359 | 0,174 (Não Sig.) |
| `renda_media_proxy` | +0,0004 | 0,0000 | 55,180 | $< 2,2 \times 10^{-16}$ *** |
| `log(populacao_total)`| +0,0396 | 0,0027 | 14,398 | $< 2,2 \times 10^{-16}$ *** |

---

## Como Executar a Replicação

### Pré-requisitos
Certifique-se de ter o R (versão $\ge$ 4.6.0) instalado. As dependências institucionais de dados (microdados do Censo e arquivos do TSE) são consumidas via API ou carregadas diretamente através do repositório público hospedado na iniciativa *Base dos Dados* via Google BigQuery.

Instale os pacotes necessários executando no console:
```R
install.packages(c("tidyverse", "factoextra", "tidymodels", "randomForest", "broom"))Hegemonia Bolsonarista no Brasil.** *Manuscrito em submissão*, 2026.
