# AprovIA — Deploy do zero

Passo a passo para subir todo o AprovIA num ambiente novo, sem dados anteriores.

| Componente | Onde roda | Como é publicado |
| --- | --- | --- |
| API Python (chat, provas, materiais) + Ollama + ChromaDB | VM na Azure | Terraform cria a VM; o cloud-init clona a `main` e instala tudo |
| API Java (usuários, login, fotos) | Azure Container Apps | GitHub Actions publica a imagem no GHCR; Terraform cria o Container App |
| PostgreSQL, Storage (Blob e Queue), Function App, monitoramento, backup, orçamento | Azure | Terraform |
| Consumidores das filas | Azure Function App | `func azure functionapp publish` |
| MongoDB | MongoDB Atlas | Painel do Atlas |
| Front-end web (Expo web, mesmo código do app) | Vercel | Importação do `aprovia-reactnative` no painel da Vercel |
| App mobile | Celular (APK) | Build local do Android |

Ordem: **código na `main` → imagem da API Java → MongoDB Atlas → Terraform → Function App → Vercel → app mobile → verificação.**

---

## 1. Pré-requisitos

Contas: Azure for Students, GitHub (repositórios `medeirosfbia/*`), MongoDB Atlas e Vercel (entre com o GitHub).

Ferramentas na sua máquina:

| Ferramenta | Para quê | Conferir |
| --- | --- | --- |
| Azure CLI | login e comandos na Azure | `az version` |
| Terraform 1.6+ | criar a infraestrutura | `terraform version` |
| Azure Functions Core Tools v4 | publicar a Function App | `func --version` |
| Node.js 20+ | app mobile | `node -v` |
| JDK 17 + Android SDK | build do APK | `java -version` |
| Git e SSH | código e acesso à VM | `ssh -V` |

## 2. Colocar o código de cada projeto na `main`

A VM, o GitHub Actions e a Vercel usam a branch `main`. Faça merge (PR ou `git merge`) e `git push` em:

| Repositório | O que precisa estar na `main` |
| --- | --- |
| `python_ProjetoIA_BackEnd` | rota `/health` e telemetria do Application Insights (`app.py`, `services/auth_service.py`, `requirements.txt`) |
| `manager_back` | Actuator (`pom.xml`, `BasicSecurityConfig.java`, `application.yaml`) e o novo `.github/workflows/ci.yml` |
| `consumers_messaging` | consumidores de histórico e de notificações |
| `aprovia-reactnative` | app mobile e front-end web, com o `vercel.json` e `"web": { "output": "single" }` no `app.json` |

## 3. Publicar a imagem da API Java

1. O push na `main` do `manager_back` dispara o workflow **Test and Deploy** (aba *Actions* do repositório). Espere os jobs `Build JAVA` e `Build and push image (GHCR)` ficarem verdes. O job de deploy na Azure só mostra uma dica por enquanto; tudo bem.
2. No GitHub, abra seu perfil > **Packages** > `manager_back` > **Package settings** > *Change visibility* > **Public**. Sem isso o Container Apps não consegue baixar a imagem.
3. Confira: `docker pull ghcr.io/medeirosfbia/manager_back:latest` (opcional).

## 4. Preparar o MongoDB Atlas

1. Crie um cluster (o gratuito M0 serve) ou use o existente.
2. **Database Access** > *Add New Database User*: usuário e senha com permissão de leitura e escrita.
3. **Network Access** > *Add IP Address* > **Allow access from anywhere** (`0.0.0.0/0`). A Function App não tem IP fixo, e o IP da VM só existe depois do Terraform.
4. **Connect** > *Drivers*: copie a connection string `mongodb+srv://...` com a senha preenchida. O banco `aprovia_db` e as coleções são criados sozinhos no primeiro uso.

## 5. Preparar a Azure

```bash
az login
az account show --query "{assinatura:name, id:id}" -o table   # anote o id

# Registra os provedores que o projeto usa (uma vez por assinatura, leva alguns minutos)
for p in Microsoft.App Microsoft.OperationalInsights Microsoft.Insights Microsoft.AlertsManagement \
         Microsoft.DBforPostgreSQL Microsoft.RecoveryServices Microsoft.Web Microsoft.Storage \
         Microsoft.Compute Microsoft.Network Microsoft.Consumption Microsoft.DevTestLab; do
  az provider register --namespace $p
done
```

Gere uma chave SSH, se ainda não tiver: `ssh-keygen -t ed25519` (a pública fica em `~/.ssh/id_ed25519.pub`).

Escolha agora o nome do projeto na Vercel (ex.: `aprovia`), porque a URL do front entra na configuração da API Python: `https://aprovia.vercel.app`.

## 6. Configurar o Terraform

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
```

Preencha o `terraform.tfvars`:

| Variável | Valor |
| --- | --- |
| `subscription_id` | id do passo 5 |
| `alert_email` | seu e-mail (alertas, orçamento e certificado HTTPS) |
| `mongo_connection_string` | connection string do passo 4 |
| `ssh_public_key` | conteúdo de `~/.ssh/id_ed25519.pub` |
| `admin_ip_cidr` | seu IP + `/32` (`curl ifconfig.me`); vazio fecha o SSH |
| `cors_origins` | `https://<projeto>.vercel.app,http://localhost:5173` |
| `java_admin_password` | senha do usuário `admin` criado na API Java |
| `expo_access_token` | token do Expo, se for enviar push; senão deixe vazio |

As demais já têm padrão: região `brazilsouth`, VM `Standard_B2ms`, 1 réplica da API Java, PostgreSQL B1ms sem HA, orçamento de US$ 20.

## 7. Criar a infraestrutura

```bash
terraform init
terraform plan -out plano.tfplan
terraform apply plano.tfplan
```

O `apply` leva de 15 a 25 minutos (o PostgreSQL é o mais demorado). No fim, anote as saídas:

```bash
terraform output api_python_url      # https://aprovia-api-xxxxx.eastus.cloudapp.azure.com
terraform output api_java_url        # https://ca-aprovia-java.<...>.azurecontainerapps.io
terraform output function_app_name
terraform output workbook_url
```

Guarde o `terraform.tfstate`: é ele que permite alterar ou destruir o ambiente depois. Ele contém senhas; não vai para o git.

## 8. Acompanhar a instalação da VM

O cloud-init instala pacotes, a API, o HTTPS e baixa os modelos do Ollama (alguns GB). Leva de 15 a 25 minutos depois do `apply`.

```bash
ssh azureuser@<host da api_python_url>
sudo tail -f /var/log/cloud-init-output.log      # termina com os "ollama pull"
sudo systemctl status aprovia ollama nginx
ollama list                                        # nomic-embed-text, qwen2-math, llama3
exit

curl https://<host da api_python_url>/health      # {"mongodb":"up","status":"ok"}
```

## 9. Publicar a Function App

```bash
cd consumers_messaging/my_func_history
func azure functionapp publish <function_app_name> --python
```

No portal, em **Function App > Functions**, devem aparecer `ConsumirHistoricoQueue`, `EnviarNotificacaoQueue`, `VerificarRecibosPush` e `EnviarLembreteDiario`.

## 10. Conferir a API Java

```bash
curl https://<api_java_url>/actuator/health       # {"status":"UP"}
```

Abra `https://<api_java_url>/swagger-ui.html` e faça login em `POST /user/login` com `admin` e a `java_admin_password`.

Deploy contínuo (opcional): para cada push na `main` atualizar o Container App sozinho, crie um service principal e salve o JSON como secret `AZURE_CREDENTIALS` no repositório `manager_back`:

```bash
az ad sp create-for-rbac --name gh-aprovia --role Contributor \
  --scopes /subscriptions/<id>/resourceGroups/rg-aprovia --sdk-auth
```

Se o tenant da faculdade não permitir criar service principal, atualize à mão depois de cada build:
`az containerapp update -n ca-aprovia-java -g rg-aprovia --image ghcr.io/medeirosfbia/manager_back:<sha do commit>`.

## 11. Publicar o front-end na Vercel

O front-end web sai do mesmo repositório do app mobile (`aprovia-reactnative`), pelo Expo. A versão em Vite
(`projetoIAWeb-front-vite`) foi descontinuada.

1. Em [vercel.com/new](https://vercel.com/new), importe o repositório `aprovia-reactnative`, com o nome de projeto escolhido no passo 5.
2. *Framework Preset*: **Other**. O `vercel.json` do repositório já define o build (`expo export -p web`), a saída `dist`
   e o redirecionamento de todas as rotas para o `index.html` (o `app.json` usa `"web": { "output": "single" }`,
   porque a rota dinâmica `/chat/[chatId]` não funciona com renderização estática).
3. *Environment Variables*:

   | Nome | Valor |
   | --- | --- |
   | `EXPO_PUBLIC_AUTH_API` | `api_java_url` |
   | `EXPO_PUBLIC_API_URL` | `api_python_url` |

4. **Deploy**. Cada push na `main` gera um novo deploy.

Se mudar as variáveis depois, faça *Redeploy*: o Expo grava os valores no build.

## 12. Gerar o app mobile

```bash
cd aprovia-reactnative
cp .env.example .env
```

No `.env`:

```bash
EXPO_PUBLIC_AUTH_API=<api_java_url>
EXPO_PUBLIC_API_URL=<api_python_url>
```

Para testar com o Expo Go: `npm install && npx expo start`.

Para gerar o APK instalável:

```bash
npm install
cd android
./gradlew assembleRelease
# APK em android/app/build/outputs/apk/release/app-release.apk
```

Passe o APK para o celular e instale (permitindo apps de fontes desconhecidas).

## 13. Verificação final

- [ ] `/health` da API Python e `/actuator/health` da API Java respondem 200.
- [ ] Front na Vercel: cadastro, login, foto de perfil (vai para o container `aprovia-profile-pictures`).
- [ ] Chat com o tutor responde em streaming e a conversa aparece no histórico (fila `aprovia-chat-history` → Function App → MongoDB).
- [ ] Upload de material como admin aparece no container `aprovia-materiais`.
- [ ] App mobile faz login e conversa com o tutor.
- [ ] Workbook (`workbook_url`) mostrando dados depois de uns 15 minutos de uso.
- [ ] Testes de disponibilidade verdes em *Application Insights > Availability*.
- [ ] Primeiro backup da VM no cofre `rsv-aprovia` (roda às 03:00; para não esperar: *Backup items > Backup now*).
- [ ] Primeiro dump do MongoDB em `aprovia-backups/mongodb/` (cron às 23:00, antes do desligamento da VM; para não esperar: `ssh` na VM e `sudo -u aprovia /usr/local/bin/aprovia-backup-mongodb`).

## Dia a dia

| Tarefa | Como |
| --- | --- |
| Atualizar a API Python | `ssh` na VM: `cd /opt/aprovia/api && sudo -u aprovia git pull && sudo -u aprovia venv/bin/pip install -r requirements.txt && sudo systemctl restart aprovia` |
| Atualizar a API Java | push na `main` do `manager_back` (passo 10) |
| Atualizar o front | push na `main` do front (Vercel faz o deploy) |
| Atualizar a Function App | repetir o passo 9 |
| Economizar crédito | `az vm deallocate -g rg-aprovia -n vm-aprovia-api` e `az vm start ...` quando for usar; ou `vm_auto_shutdown = true` |
| Demonstrar HA do PostgreSQL | `postgres_high_availability = true` + `terraform apply`; voltar para `false` no mesmo dia (~US$ 0,35 a 0,50 por hora) |
| Apagar tudo | remover o bloco `prevent_destroy` em `postgres.tf` e rodar `terraform destroy` |

## Problemas comuns

| Sintoma | Causa e solução |
| --- | --- |
| `apply` falha com cota de vCPU (`OperationNotAllowed`) | A conta de estudante tem limite por região: use `vm_size = "Standard_B2s"` ou outra `location` |
| Function App não cria (`Dynamic` / `Y1` indisponível) | Plano Consumption Linux sem cota na região: troque a `location` |
| Erro no orçamento (`budget`) | Oferta sem suporte a orçamento pela API: `budget_amount = 0` |
| Container App em falha, sem réplica | Imagem do GHCR ainda privada ou inexistente (passo 3) |
| `/health` responde 503 | MongoDB inacessível: confira o `0.0.0.0/0` no Atlas e a connection string |
| HTTPS não funciona na VM | O certbot falhou na instalação: `ssh` na VM e `sudo certbot --nginx -d <host> --redirect` |
| Front recebe erro de CORS da API Python | URL da Vercel fora do `cors_origins`: edite `/etc/aprovia/api.env` na VM e `sudo systemctl restart aprovia` |
| Chat muito lento | VM sem GPU; `vm_size = "Standard_B4ms"` (16 GB) ajuda, custando o dobro |

## Custos (conta Azure for Students, aproximados)

| Recurso | Custo |
| --- | --- |
| VM `Standard_B2ms` ligada 24 h | ~US$ 60/mês, o maior gasto |
| API Java, 1 réplica sempre ligada (0,5 vCPU, 1 GiB) | ~US$ 10 a 15/mês |
| PostgreSQL B1ms, Function App, Storage, Log Analytics (até 5 GB) | gratuito ou poucos dólares |
| `postgres_high_availability = true` | ~US$ 250/mês: só para a demonstração |

Com tudo ligado o tempo todo, o crédito de US$ 100 acaba em menos de 2 meses; o orçamento de US$ 20 avisa por e-mail antes.
 