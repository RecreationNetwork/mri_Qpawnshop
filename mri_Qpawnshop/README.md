# mri_Qpawnshop 3.0.2

Correções do computador, criação de lojas, compra da propriedade, avaliação, vendas, penhores, resgates, prateleiras, depósitos, embalagem, fornecedores, exportações, frota e interface.

## Aplicar

Reinicie o servidor para carregar também os itens adicionados ao catálogo do `mri_Qbox`: `pawn_package`, `silverbar` e `old_coin`. As novas tabelas de lotes e coletas são criadas automaticamente, sem apagar tabelas ou dados existentes.

Se o inventário já foi recarregado, basta executar no console:

```text
restart mri_Qpawnshop
```

A tentativa de reinício automático pelo txAdmin foi recusada por falta de permissão da conta conectada. Não foram alteradas permissões do painel.

## Placa e propriedade

Com autorização do usuário, a loja #1 (`Penhor Mirror Park`) foi colocada novamente à venda: `owner_cid = NULL`, `ownable = 1`. Seu saldo e os demais registros foram preservados. A alteração será lida pelo recurso no próximo reinício.

A placa usa `Config.ForSaleSignModel`, com padrão `prop_forsale_lrg_01`, existente no catálogo local de objetos. O prop carrega quando o jogador fica a até 100 metros, usa o chão e as dimensões do modelo para o posicionamento, recebe a rotação salva e oferece compra pelo `mri_Qinteract`. A placa desaparece quando a loja é adquirida.

Os pontos de compra, computador, embalagem, prateleiras, garagem e fornecedores usam apenas os prompts do `mri_Qinteract`. O aviso lateral duplicado da placa foi removido. As instruções do editor administrativo de posicionamento continuam separadas das interações de jogadores.

Backups estão em `backup_scripts/mri_Qpawnshop_full_20261014-222003`, no backup específico de propriedade `pawnshop_shop1_ownership_*.sql` e no backup de itens `pawnshop_base_items_*.lua`.

## Comportamentos corrigidos

- Computador e avaliação reutilizam funções locais no servidor; não chamam callbacks do cliente com nomes de callbacks do servidor.
- Operações verificam distância, permissão, números válidos e limites. Uma trava por loja e jogador evita operações concorrentes com o mesmo saldo ou estoque.
- Depósitos privados têm verificações de abertura e movimentação no inventário; bancadas de avaliação são individuais.
- A avaliação usa o valor configurado do item, impedindo que aumentar o preço de revenda gere dinheiro na recompra. Planos de fidelidade vencidos não dão bônus.
- Falhas de entrega em compras e resgates devolvem o pagamento. Falhas SQL em vendas e penhores devolvem os itens à bancada.
- Penhores respeitam o limite configurado. Resgates e expiração não processam a mesma loja simultaneamente.
- Metadados são preservados nos penhores, resgates, lotes vendidos e caixas. Estoque antigo sem metadados permanece utilizável, mas informações perdidas por versões anteriores não podem ser reconstruídas.
- No computador, “Abastecer estoque de vendas” e “Abastecer ofertas especiais” transferem os respectivos depósitos para as prateleiras virtuais.
- Fornecedores usam a lista paga registrada no servidor. O cliente não escolhe os itens ou quantidades entregues. Coletas pagas não concluídas são devolvidas ao caixa ao desconectar ou reiniciar o recurso.
- Exportações exigem uma missão ativa do jogador, presença no destino e a quantidade total correta. Caixas precisam pertencer à loja e conter o item solicitado. Também é possível completar o restante com unidades avulsas.
- Frota é criada e guardada no servidor, com autorização e estado persistente. Há limite por modelo, verificação de saída ocupada e proteção contra retirada duplicada. Seguro não recupera um veículo que ainda existe em circulação.
- A NUI escapa textos recebidos, trata falhas de comunicação, limita cliques repetidos e filtra aplicativos por permissão. E-mails confidenciais são filtrados no servidor.

As operações entre inventário, dinheiro do jogador e MySQL utilizam compensação em falhas previsíveis; uma interrupção abrupta do processo no meio de uma operação ainda exige conferência dos registros. Coletas iniciadas por versões anteriores não possuem registro persistente de missão.

## Testes

Execute a partir da raiz do workspace, com Lua 5.3+ e Node:

```text
lua "resources/[mri_beta]/mri_Qpawnshop/tests/server.test.lua"
lua "resources/[mri_beta]/mri_Qpawnshop/tests/sign.test.lua"
node "resources/[mri_beta]/mri_Qpawnshop/tests/nui.test.js"
```

Validados: 20 cenários de servidor, 7 da placa e 8 da NUI, além da sintaxe Lua/JavaScript e arquivos do manifesto. Os testes Lua também funcionam na VM Fengari utilizada neste workspace. Os testes usam mocks; a aparência e a interação dentro do FiveM precisam ser conferidas após aplicar o reinício.
