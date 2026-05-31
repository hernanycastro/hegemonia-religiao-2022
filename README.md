# “The Census of the Saved”: Religious Territories and Bolsonarist Hegemony in Brazil

Repositório oficial contendo o pipeline de dados, scripts de modelagem multivariada e rotinas de aprendizado de máquina aplicados no artigo *“O Censo dos Salvos”: Territórios Religiosos e Hegemonia Bolsonarista no Brasil*.

O projeto investiga a articulação entre as formações religiosas territorializadas e o fenômeno eleitoral nas eleições presidenciais de 2022, utilizando o arcabouço pós-estruturalista de Ernesto Laclau e Chantal Mouffe.

## 📊 Desenho Metodológico e Modelagem

A arquitetura empírica adota uma abordagem relacional baseada em taxas proporcionais e eixos socioeconômicos regionalizados por município (controlados por meio de uma proxy de renda estrutural baseada no rendimento médio histórico das Unidades da Federação). O pipeline executa três técnicas integradas:

1. **Análise de Componentes Principais (PCA):** Mapeamento das coordenadas latentes do campo discursivo. Além dos eixos tradicionais (PC1 e PC2), o modelo estende a observação de forma exploratória à terceira dimensão (PC3 = 0,99 de autovalor), retendo um total robusto de 78,42% da variância explicada.
2. **Modelagem Preditiva (Random Forest):** Algoritmo supervisionado para mensurar o peso de importância por permutação das fraturas socioeconômicas e confessionais no voto do segundo turno.
3. **Agrupamento Territorial (K-Means):** Algoritmo não supervisionado aplicado sobre a malha de proporções escalonadas para a extração de uma tipologia discreta de três macro-perfis socio-religiosos no território brasileiro.

## 📂 Estrutura do Repositório

* `censo_salvos.R`: Script unificado e comentado contendo toda a rotina de carregamento de pacotes, extração via API, engenharia de recursos, modelagem multivariada e exportação de resultados.
* `/resultados_eleicao/`: Diretório gerado automaticamente pelo script para salvar tabelas de coeficientes (`.csv`) e gráficos de diagnóstico (`.png`).

## 🛠️ Tecnologias e Pacotes Utilizados

O pipeline foi inteiramente desenvolvido em linguagem **R (versão ≥ 4.6.0)**. O script utiliza o gerenciador de dependências `pacman` e mobiliza as seguintes engines:

* `electionsBR`: Raspagem automatizada de dados oficiais de candidaturas do TSE.
* `basedosdados`: Conexão programática via BigQuery (Google Cloud) para extração direta do Censo IBGE e dos resultados eleitorais por município.
* `tidyverse`: Manipulação, tratamento e engenharia de recursos.
* `tidymodels` & `ranger`: Framework de Machine Learning e engine de alta performance para florestas aleatórias.
* `factoextra`: Extração e visualização gráfica dos resultados da PCA e K-Means.

## 🚀 Como Executar e Replicar a Análise

### 1. Autenticação no Google Cloud
Os dados brutos são extraídos diretamente do BigQuery por meio da API da *Base dos Dados*. Para rodar o pipeline, você precisará de um projeto ativo (gratuito) no Google Cloud Sandbox para gerar seu ID de faturamento.

### 2. Execução
Clone este repositório e execute a rotina no console do RStudio:

```R
# Insira seu ID de faturamento validado do Google Cloud na linha correspondente do script:
# set_billing_id("seu-projeto-gcp")

# Execute o arquivo de replicação
source("censo_salvos.R")

📜 Licença e Citação
Este repositório está sob a licença MIT. Os dados e scripts são de livre acesso para fins de auditoria científica, replicação e avanço da pesquisa social quantitativa.

Se este código for útil para a sua pesquisa, por favor, cite o trabalho correspondente:

CASTRO, Hernany Gomes de; GRACINO JUNIOR, Paulo; SILVA, Mayra Goulart da. **“O Censo dos Salvos”: Territórios Religiosos e Hegemonia Bolsonarista no Brasil.** *Manuscrito em submissão*, 2026.
