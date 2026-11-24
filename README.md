# OCI Ampere A1 Always Free — automação via GitHub Actions

Cria automaticamente uma VM **VM.Standard.A1.Flex — 2 OCPU / 12 GB, Ubuntu 24.04** no free tier da Oracle, tentando de madrugada quando aparece capacidade.

## Por que GitHub Actions

- **Vercel** não serve: 10s (hobby) / 60s (pro) por function.
- **GitHub Actions** permite cron e job de até 6h. Free: 2000 min/mês em repo privado.

## Arquivos

| Arquivo | Função |
|---|---|
| `.github/workflows/oci-a1.yml` | Cron diário 05:00 UTC (02:00 BRT) + disparo manual |
| `oci-a1-launch.sh` | 20 tentativas de launch, 60s entre elas |
| `.gitattributes` | Força LF no `.sh` (senão quebra no Ubuntu runner) |
| `.gitignore` | Impede commit acidental de chaves/config |

## 1. Subir esta pasta

A pasta `oci-a1-github` é a raiz do repositório. Entre nela:

```powershell
cd C:\Users\miche\Documents\Padrao\oci-a1-github
git init
git add .
git commit -m "OCI A1 auto launch"
git remote add origin https://github.com/<seu-usuario>/<seu-repo>.git
git push -u origin main
```

O `.gitignore` já bloqueia `*.pem`, `*.pub`, `config`, `launch.log` etc.

## 2. Pegar os valores no seu PC

```powershell
Get-Content "$HOME\.oci\config"
Get-Content "$HOME\.ssh\id_ed25519_oci.pub"
```

Chave de API em base64 (vai para um Secret):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\.oci\oci_api_key.pem")) | clip
```

## 3. Criar os Secrets

Repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Nome | Valor |
|---|---|
| `OCI_USER` | `ocid1.user...` do config |
| `OCI_TENANCY` | `ocid1.tenancy...` do config |
| `OCI_FINGERPRINT` | fingerprint do config |
| `OCI_REGION` | `sa-saopaulo-1` |
| `OCI_PRIVATE_KEY_B64` | string base64 gerada acima |
| `OCI_SUBNET_ID` | `ocid1.subnet.oc1.sa-saopaulo-1...` |
| `OCI_IMAGE_ID` | `ocid1.image.oc1.sa-saopaulo-1...` (Ubuntu 24.04 ARM) |
| `OCI_AD` | `wlnJ:SA-SAOPAULO-1-AD-1` |
| `OCI_SSH_PUBLIC_KEY` | linha completa do `.pub` (`ssh-ed25519 AAAA...`) |

Segurança: a chave de API fica mascarada nos logs, mas continua sendo credencial viva. O ideal é um **usuário IAM dedicado** com permissão só de Compute + rede.

## 4. Testar e acompanhar

Actions → **OCI Ampere A1 Always Free** → **Run workflow**.

Se der `Out of host capacity`, o job tenta 20 vezes (20 min). Quando conseguir, baixe o artifact `oci-a1-result`: ele contém `vm-info.txt` com o IP público.

Depois **desative o workflow** (Actions → workflow → Disable workflow) para não continuar tentando.

## 5. Conectar

A chave privada nunca sai da sua máquina:

```powershell
ssh -i "$HOME\.ssh\id_ed25519_oci" ubuntu@<IP_DO_ARTIFACT>
```

## Ajustes

- Horário: `cron` é UTC. `0 5 * * *` = 02:00 BRT. Para cada 2h: `0 */2 * * *`.
- Tentativas: `MAX_ATTEMPTS` no workflow (respeite `timeout-minutes: 30`).
- GitHub desativa cron em repos sem atividade por 60 dias — faça um commit de vez em quando.
