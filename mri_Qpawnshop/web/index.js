let computerData = null;
let currentApp = 'shop_manager';
let selectedCategory = 'household_items';
let actionPending=false,actionTimer=null;
function escapeHTML(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
}
function allowed(permission) {
    const perms=(computerData && computerData.permissions)||{};
    return Boolean(perms.admin || perms[permission]);
}
const APP_PERMISSION={funds:'manage_funds',inventory:'set_prices',vehicles:'manage_vehicles',exports:'start_exports',collections:'accept_suppliers',emails:'view_emails',workers:'hire_workers',loyalty:'manage_loyalty'};
function releaseAction(){actionPending=false;clearTimeout(actionTimer);root.querySelectorAll('button').forEach(button=>{if(button.dataset.pendingDisabled!==undefined){button.disabled=button.dataset.pendingDisabled==='true';delete button.dataset.pendingDisabled;}});}
function showError(message){let banner=document.getElementById('request-error');if(!banner){banner=document.createElement('p');banner.id='request-error';banner.setAttribute('role','alert');root.appendChild(banner);}banner.textContent=message;}


const root = document.getElementById('desktop-root');
const desktopIcons = document.getElementById('desktop-icons');
const ifruitDock = document.getElementById('ifruit-dock');
const winTitle = document.getElementById('win-title');
const winIcon = document.getElementById('win-icon');
const winBody = document.getElementById('win-body');
const osVersionLabel = document.getElementById('os-version-label');

const APPS = [
    { id: 'shop_manager', label: 'Gestão da Loja',     icon: 'fa-sliders',            color: '#6366f1' },
    { id: 'loyalty',      label: 'Fidelidade',         icon: 'fa-id-card',            color: '#f59e0b' },
    { id: 'workers',      label: 'Funcionários',       icon: 'fa-users-gear',         color: '#10b981' },
    { id: 'handbook',     label: 'Manual da Equipe',   icon: 'fa-book-open',          color: '#64748b' },
    { id: 'funds',        label: 'Caixa da Empresa',   icon: 'fa-sack-dollar',        color: '#22c55e' },
    { id: 'top_workers',  label: 'Ranking da Equipe',  icon: 'fa-star',               color: '#eab308' },
    { id: 'inventory',    label: 'Estoque & Preços',   icon: 'fa-boxes-stacked',      color: '#d97706' },
    { id: 'payroll',      label: 'Folha Salarial',     icon: 'fa-money-check-dollar', color: '#16a34a' },
    { id: 'vehicles',     label: 'Frota de Veículos',  icon: 'fa-van-shuttle',        color: '#8b5cf6' },
    { id: 'exports',      label: 'Exportações',        icon: 'fa-paper-plane',        color: '#06b6d4' },
    { id: 'collections',  label: 'Fornecedores',       icon: 'fa-truck-ramp-box',     color: '#3b82f6' },
    { id: 'emails',       label: 'E-mails',            icon: 'fa-envelope',           color: '#ef4444' }
];

const STATUS_LABELS = {
    pending: 'PENDENTE',
    active: 'EM ANDAMENTO',
    completed: 'CONCLUÍDO',
    denied: 'RECUSADO',
    available: 'DISPONÍVEL'
};

function money(val) {
    return '$' + Number(val || 0).toLocaleString('pt-BR');
}

function post(endpoint, payload) {
    return fetch(`https://${GetParentResourceName()}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {})
    }).then(response=>{if(!response.ok)throw Error('HTTP '+response.status);return response.json();}).then(result=>{if(result && result.ok===false)throw Error('Operação recusada');return result;}).catch(error=>{showError('Falha de comunicação. Tente novamente.');releaseAction();return {ok:false};});
}

function sendAction(action, data) {
    if(actionPending)return;
    actionPending=true;
    root.querySelectorAll('button').forEach(button=>{button.dataset.pendingDisabled=String(button.disabled);button.disabled=true;});
    actionTimer=setTimeout(()=>{releaseAction();},3000);
    post('computerAction',{action,data}).then(result=>{if(!result || result.ok===false)releaseAction();});
}

function renderShell() {
    if (!computerData) return;
    const isIfruit = computerData.shop.os_theme === 'ifruit';
    root.className = isIfruit ? 'os-ifruit' : 'os-classic';
    osVersionLabel.textContent = isIfruit ? 'iFruit OS Pro' : 'Sistema Clássico v1.0';

    desktopIcons.innerHTML = '';
    ifruitDock.innerHTML = '';

    APPS.filter(app=>!APP_PERMISSION[app.id] || allowed(APP_PERMISSION[app.id])).forEach(app=>{
        const iconBtn = document.createElement('button');
        iconBtn.type = 'button';
        iconBtn.className = 'desktop-icon-btn' + (currentApp === app.id ? ' active' : '');
        iconBtn.innerHTML = `
            <div class="desktop-icon-box" style="background:${app.color}">
                <i class="fa-solid ${app.icon}"></i>
            </div>
            <span>${app.label}</span>
        `;
        iconBtn.onclick = () => openApp(app.id);
        desktopIcons.appendChild(iconBtn);

        const dockBtn = document.createElement('button');
        dockBtn.type = 'button';
        dockBtn.className = 'dock-btn';
        dockBtn.style.background = app.color;
        dockBtn.title = app.label;
        dockBtn.innerHTML = `<i class="fa-solid ${app.icon}"></i>`;
        dockBtn.onclick = () => openApp(app.id);
        ifruitDock.appendChild(dockBtn);
    });

    renderCurrentApp();
}

function openApp(appId) {
    if(APP_PERMISSION[appId] && !allowed(APP_PERMISSION[appId]))return;
    currentApp=appId;
    renderShell();
}

function renderCurrentApp() {
    const appMeta = APPS.find(a => a.id === currentApp) || APPS[0];
    winTitle.textContent = appMeta.label;
    winIcon.className = `fa-solid ${appMeta.icon}`;

    const s = computerData.shop;
    const stats = s.stats || {};
    const catLabels = computerData.categoryLabels || {};

    if (currentApp === 'shop_manager') {
        winBody.innerHTML = `
            <div class="panel-grid">
                <div class="stat-box">
                    <div class="stat-label">Estabelecimento</div>
                    <div class="stat-value" style="color:inherit;font-size:18px;">${escapeHTML(s.name)}</div>
                    <div style="font-size:12px;margin-top:4px;">Seu Cargo: <b>${escapeHTML(computerData.role)}</b></div>
                </div>
                <div class="stat-box">
                    <div class="stat-label">Saldo em Caixa</div>
                    <div class="stat-value">${money(s.funds)}</div>
                </div>
                <div class="stat-box">
                    <div class="stat-label">Nível & Experiência</div>
                    <div class="stat-value">Nível ${s.level} (${escapeHTML(computerData.levelInfo.name)})</div>
                    <div style="font-size:12px;margin-top:4px;">XP: ${s.xp} • Avaliação: ⭐ ${Number(s.rating).toFixed(1)}</div>
                </div>
                <div class="stat-box">
                    <div class="stat-label">Resumo Operacional</div>
                    <div class="stat-value">${stats.itemsSold || 0} Vendas</div>
                    <div style="font-size:12px;margin-top:4px;">Penhores Ativos: ${computerData.activePawns} | Exportações: ${stats.completedExports || 0}</div>
                </div>
            </div>

            <div class="section-card">
                <div class="section-title">⚙️ Controles de Funcionamento da Loja</div>
                ${[
                    { key: 'is_open',               label: 'Status da Loja (Aberta ao Público)' },
                    { key: 'buying_active',         label: 'Compra e Penhor de Mercadorias no Balcão' },
                    { key: 'special_offers_active', label: 'Vitrine de Ofertas Especiais' },
                    { key: 'collections_active',    label: 'Missões de Coleta de Fornecedores' },
                    { key: 'exports_active',        label: 'Recebimento de Pedidos de Exportação' }
                ].map(ctrl => `
                    <div class="row-item">
                        <span>${ctrl.label}</span>
                        <button class="btn ${s[ctrl.key] ? 'btn-green' : 'btn-red'}" onclick="sendAction('toggleControl', {field:'${ctrl.key}'})">
                            ${s[ctrl.key] ? 'ATIVO / ABERTO' : 'DESATIVADO / FECHADO'}
                        </button>
                    </div>
                `).join('')}
            </div>

            <div class="section-card">
                <div class="section-title">📊 Histórico Recente de Atividades</div>
                ${(computerData.logs || []).slice(0, 8).map(l => `
                    <div class="row-item">
                        <span><b>[${l.log_type.toUpperCase()}]</b> ${escapeHTML(l.actor)}:${escapeHTML(l.description)}</span>
                        <b>${l.amount ? money(l.amount) : ''}</b>
                    </div>
                `).join('') || '<p>Nenhum registro de atividade até o momento.</p>'}
            </div>
        `;
    } else if (currentApp === 'funds') {
        winBody.innerHTML = `
            <div class="section-card" style="max-width:460px;margin:20px auto;text-align:center;">
                <div class="stat-label">Saldo Disponível no Caixa da Empresa</div>
                <div class="stat-value" style="font-size:32px;margin:12px 0;">${money(s.funds)}</div>
                <input type="number" id="funds-input" class="input-field" placeholder="Digite o valor..." style="width:100%;margin-bottom:12px;">
                <div style="display:flex;gap:10px;justify-content:center;">
                    <button class="btn btn-green" onclick="sendAction('fundsTransaction', {kind:'deposit', amount:document.getElementById('funds-input').value})">
                        <i class="fa-solid fa-arrow-up"></i> Depositar
                    </button>
                    <button class="btn btn-red" onclick="sendAction('fundsTransaction', {kind:'withdraw', amount:document.getElementById('funds-input').value})">
                        <i class="fa-solid fa-arrow-down"></i> Sacar
                    </button>
                </div>
            </div>
        `;
    } else if (currentApp === 'inventory') {
        const items = (computerData.inventory || []).filter(i => i.category === selectedCategory);
        const currentCatLabel = catLabels[selectedCategory] || selectedCategory;
        winBody.innerHTML = `
            <div style="display:flex;gap:10px;margin-bottom:14px;flex-wrap:wrap;">
                <button class="btn btn-blue" onclick="post('openStashFromPC', {stashId:'pawnshop_${s.id}_intake'})">📥 Abrir Depósito de Entrada</button>
                <button class="btn btn-green" onclick="sendAction('stockIntake',{})">Abastecer estoque de vendas</button>
                <button class="btn btn-amber" onclick="sendAction('stockSpecialOffers',{})">Abastecer ofertas especiais</button>
                <button class="btn btn-amber" onclick="post('openStashFromPC', {stashId:'pawnshop_${s.id}_special_offers'})">⭐ Abrir Baú de Ofertas Especiais</button>
                <button class="btn btn-green" onclick="post('placeNewShelf', {category:'${selectedCategory}'})">➕ Posicionar Prateleira (${escapeHTML(currentCatLabel)})</button>
            </div>
            <div style="display:grid;grid-template-columns:230px 1fr;gap:16px;">
                <div class="section-card">
                    <div class="section-title">Categorias</div>
                    ${Object.keys(s.categories || {}).filter(k => s.categories[k]).map(catKey => `
                        <div class="row-item" style="cursor:pointer;font-weight:${selectedCategory === catKey ? '800' : '500'}" onclick="selectedCategory='${catKey}';renderCurrentApp();">
                            <span>${catLabels[catKey] || catKey}</span>
                        </div>
                    `).join('')}
                </div>
                <div class="section-card">
                    <table class="data-table">
                        <thead>
                            <tr><th>Mercadoria</th><th>Estoque</th><th>Preço de Venda</th><th>Preço Sugerido</th><th>Ação</th></tr>
                        </thead>
                        <tbody>
                            ${items.map(it => `
                                <tr>
                                    <td><b>${escapeHTML(it.label)}</b></td>
                                    <td>${it.qty} un.</td>
                                    <td><input type="number" id="price-${it.id}" class="input-field" value="${it.price}" style="width:95px;"></td>
                                    <td>${money(it.rrp)}</td>
                                    <td>
                                        <button class="btn btn-green" onclick="sendAction('updateItemPrice', {itemId:${it.id}, price:document.getElementById('price-${it.id}').value})">Salvar</button>
                                    </td>
                                </tr>
                            `).join('') || '<tr><td colspan="5">Nenhum item cadastrado nesta categoria.</td></tr>'}
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    } else if (currentApp === 'exports') {
        winBody.innerHTML = `
            <div class="section-card">
                <div class="section-title">📤 Contratos de Exportação (Multiplicador do Nível: x${computerData.levelInfo.exportBonus})</div>
                ${(computerData.exports || []).map(ord => `
                    <div class="row-item">
                        <div>
                            <b>${ord.qty}x${escapeHTML(ord.item_label)}</b>
                            <div style="font-size:12px;opacity:0.8;">Recompensa: ${money(ord.payout)} • +${ord.xp_reward} XP • Status: <b>${STATUS_LABELS[ord.status] || ord.status.toUpperCase()}</b></div>
                        </div>
                        <div style="display:flex;gap:8px;">
                            ${ord.status === 'pending' ? `
                                <button class="btn btn-green" onclick="sendAction('acceptExportOrder', {orderId:${ord.id}})">Aceitar</button>
                                <button class="btn btn-red" onclick="sendAction('denyExportOrder', {orderId:${ord.id}})">Recusar</button>
                            ` : ''}
                            ${ord.status === 'active' ? `
                                <button class="btn btn-blue" onclick="sendAction('startExportDelivery', {orderId:${ord.id}})">🚚 Iniciar Entrega</button>
                            ` : ''}
                        </div>
                    </div>
                `).join('') || '<p>Nenhum pedido de exportação disponível no momento.</p>'}
            </div>
        `;
    } else if (currentApp === 'collections') {
        const sup = computerData.supplier || { offers: [], queue: [] };
        winBody.innerHTML = `
            <div class="section-card">
                <div class="section-title">
                    <span>🚚 Fila de Coleta (${sup.queue.length} lote(s) selecionado(s))</span>
                    ${sup.queue.length > 0 ? `<button class="btn btn-green" onclick="sendAction('startSupplierMission', {})">▶ Iniciar Missão de Coleta</button>` : ''}
                </div>
                ${sup.queue.map(q => `
                    <div class="row-item">
                        <span><b>${q.qty}x${escapeHTML(q.label)}</b></span>
                        <span>Custo: ${money(q.cost)}</span>
                    </div>
                `).join('') || '<p>A fila de coleta está vazia. Adicione ofertas de fornecedores abaixo.</p>'}
            </div>
            <div class="section-card">
                <div class="section-title">📦 Ofertas Disponíveis dos Fornecedores</div>
                ${sup.offers.map(off => `
                    <div class="row-item">
                        <div>
                            <b>${off.qty}x ${escapeHTML(off.label)}</b>${off.rare ? '<span style="color:#f59e0b;font-weight:800;">[LOTE RARO]</span>' : ''}
                            <div style="font-size:12px;">Custo do Fornecedor: ${money(off.cost)}</div>
                        </div>
                        <button class="btn btn-green" onclick="sendAction('addSupplierToQueue', {offerId:${off.id}})">+ Adicionar à Fila</button>
                    </div>
                `).join('') || '<p>Todas as ofertas atuais já foram adicionadas à fila.</p>'}
            </div>
        `;
    } else if (currentApp === 'workers') {
        winBody.innerHTML = `
            <div class="section-card">
                <div class="section-title">👥 Contratar Pessoas Próximas</div>
                ${(computerData.nearbyPlayers || []).map(p => `
                    <div class="row-item">
                        <span>${escapeHTML(p.name)} (${escapeHTML(p.citizenid)})</span>
                        <button class="btn btn-green" onclick='sendAction("hireWorker", {citizenid:${escapeHTML(JSON.stringify(p.citizenid))}})'>+ Contratar</button>
                    </div>
                `).join('') || '<p>Nenhum cidadão próximo encontrado.</p>'}
            </div>
            <div class="section-card">
                <div class="section-title">👔 Quadro de Funcionários & Cargos</div>
                ${(computerData.workers || []).map(w => `
                    <div class="row-item">
                        <div>
                            <b>${escapeHTML(w.name)}</b> — Cargo Atual: <b>${escapeHTML(w.role_preset)}</b> (Reputação Nv.${w.rep_level})
                        </div>
                        <div style="display:flex;gap:8px;flex-wrap:wrap;">
                            ${['Gerente', 'Estoquista', 'Motorista', 'Caixa'].map(preset => `
                                <button class="btn btn-blue" onclick='sendAction("updateWorkerPermissions", {workerId:${w.id}, preset:"${preset}", permissions:${JSON.stringify(computerData.presets[preset])}})'>${preset}</button>
                            `).join('')}
                            <button class="btn btn-red" onclick="sendAction('fireWorker', {workerId:${w.id}})">Demitir</button>
                        </div>
                    </div>
                `).join('') || '<p>Nenhum funcionário contratado até o momento.</p>'}
            </div>
        `;
    } else if (currentApp === 'vehicles') {
        winBody.innerHTML = `
            <div class="section-card">
                <div class="section-title">🚐 Frota Ativa da Empresa (${(computerData.vehicles || []).length})</div>
                ${(computerData.vehicles || []).map(v => `
                    <div class="row-item">
                        <div>
                            <b>${escapeHTML(v.label)}</b> — Placa: <b>${escapeHTML(v.plate)}</b> (${STATUS_LABELS[v.status] || v.status.toUpperCase()})
                            <div style="font-size:12px;">Combustível: ${v.fuel}% | Lataria: ${v.body}\% \vert{} Motor:${v.engine}%</div>
                        </div>
                        <button class="btn btn-amber" onclick="sendAction('claimInsurance', {vehicleId:${v.id}})">Acionar Seguro (${money(v.insurance_cost)})</button>
                    </div>
                `).join('') || '<p>Nenhum veículo adquirido na frota.</p>'}
            </div>
            <div class="section-card">
                <div class="section-title">🛒 Adquirir Novos Veículos (Nível Atual da Loja: ${s.level})</div>
                ${(computerData.fleetCatalog || []).map(fc => `
                    <div class="row-item">
                        <div>
                            <b>${escapeHTML(fc.label)}</b> (Requer Nível ${fc.minLevel})
                            <div style="font-size:12px;">Capacidade: ${fc.slots} espaços • Franquia do Seguro: ${money(fc.insurance)}</div>
                        </div>
                        <button class="btn btn-green" ${s.level < fc.minLevel ? 'disabled' : ''} onclick="sendAction('buyFleetVehicle', {model:'${fc.model}'})">
                            ${fc.price === 0 ? 'Resgatar Grátis' : 'Comprar ' + money(fc.price)}
                        </button>
                    </div>
                `).join('')}
            </div>
        `;
    } else if (currentApp === 'loyalty') {
        winBody.innerHTML = `
            <div class="section-card">
                <div class="section-title">💳 Clientes Cadastrados no Programa de Fidelidade (${(computerData.loyalty || []).length})</div>
                ${(computerData.loyalty || []).map(m => `
                    <div class="row-item">
                        <span><b>${escapeHTML(m.customer_name)}</b> — Plano: <b>${escapeHTML(m.tier)}</b></span>
                        <span>${m.points} pontos (${money(m.total_spent)} movimentados)</span>
                    </div>
                `).join('') || '<p>Nenhum cliente inscrito no programa de fidelidade ainda.</p>'}
            </div>
        `;
    } else if (currentApp === 'payroll') {
        const pts = (computerData.myWorker && computerData.myWorker.unclaimed_points) || 0;
        winBody.innerHTML = `
            <div class="section-card" style="max-width:500px;margin:20px auto;text-align:center;">
                <div class="stat-label">Seus Pontos de Produtividade Acumulados</div>
                <div class="stat-value" style="font-size:30px;margin:10px 0;">${Number(pts).toFixed(2)} pts</div>
                <p style="font-size:13px;margin-bottom:14px;">Pagamento Estimado: <b>${money(pts * (computerData.payrollPointRate || 50))}</b> • Isenção Fiscal da Loja: <b>${Math.round(computerData.levelInfo.taxRelief * 100)}%</b></p>
                <button class="btn btn-green" onclick="sendAction('claimPayslip', {})">💵 Emitir e Receber Holerite</button>
            </div>
        `;
    } else if (currentApp === 'top_workers') {
        winBody.innerHTML = `
            <div class="section-card">
                <div class="section-title">⭐ Ranking de Desempenho dos Funcionários</div>
                ${(computerData.workers || []).map((w, idx) => `
                    <div class="row-item">
                        <span><b>#${idx + 1} ${escapeHTML(w.name)}</b> (${escapeHTML(w.role_preset)})</span>
                        <span>Nível de Reputação ${w.rep_level} (${w.rep_xp} XP)</span>
                    </div>
                `).join('') || '<p>Nenhum funcionário registrado no ranking.</p>'}
            </div>
        `;
    } else if (currentApp === 'handbook') {
        winBody.innerHTML = `
            <div class="section-card">
                <div class="section-title">📖 Manual da Equipe — Procedimentos Operacionais Padrão</div>
                <p style="line-height:1.75;font-size:13px;">
                    1. <b>Avaliação no Balcão:</b> Os clientes depositam os itens na Bancada de Avaliação e escolhem entre a Venda Imediata à vista (80%) ou o Penhor com prazo de 72 horas (60%).<br>
                    2. <b>Penhores Expirados:</b> Qualquer item penhorado que não for resgatado pelo cliente dentro de 72 horas é transferido automaticamente para o estoque de vendas da loja.<br>
                    3. <b>Embalagem e Exportações:</b> Aceite contratos no aplicativo "Exportações", embale os itens na Estação de Embalagem e transporte as caixas sem correr para não tropeçar.<br>
                    4. <b>Atualização iFruit OS Pro:</b> Ao alcançar o Nível 3 da loja, verifique sua Caixa de Entrada no aplicativo "E-mails" para instalar gratuitamente o novo sistema operacional escuro!
                </p>
            </div>
        `;
    } else if (currentApp === 'emails') {
        winBody.innerHTML = `
            <div class="section-card">
                <div class="section-title">📧 Caixa de Entrada Corporativa</div>
                ${(computerData.emails || []).map(mail => `
                    <div class="section-card" style="margin-bottom:10px;">
                        <div style="display:flex;justify-content:space-between;margin-bottom:6px;">
                            <b>${escapeHTML(mail.subject)}</b>
                            <span style="font-size:11px;opacity:0.75;">De: ${escapeHTML(mail.sender)}</span>
                        </div>
                        <pre style="white-space:pre-wrap;font-family:inherit;font-size:12px;margin-bottom:10px;">${escapeHTML(mail.body)}</pre>${mail.action_type && mail.action_status === 'none' ? `
                            <button class="btn btn-green" onclick="sendAction('acceptEmailAction', {emailId:${mail.id}})">✔ Aceitar Oferta / Instalar Atualização</button>
                        ` : (mail.action_status !== 'none' ? `<span style="color:#10b981;font-size:12px;font-weight:700;">✔ Oferta Aceita / Instalada</span>` : '')}
                    </div>
                `).join('') || '<p>A caixa de entrada está vazia.</p>'}
            </div>
        `;
    }
}

function closeOS(){
    post('closeComputer',{}).then(result=>{if(result.ok){root.style.display='none';computerData=null;releaseAction();}});
}

window.addEventListener('message', event => {
    const msg = event.data || {};
    if (msg.action === 'openComputer' && msg.data) {
        if(msg.data.denied || !msg.data.shop)return;
        releaseAction();
        computerData=msg.data;
        const available=Object.keys(computerData.shop.categories||{}).filter(key=>computerData.shop.categories[key]);
        if(!available.includes(selectedCategory))selectedCategory=available[0]||'general_goods';
        currentApp = 'shop_manager';
        root.style.display = 'flex';
        renderShell();
    } else if (msg.action === 'refreshComputer' && msg.data) {
        if(!computerData || msg.data.shop.id!==computerData.shop.id)return;
        computerData=msg.data;
        releaseAction();
        renderShell();
    } else if (msg.action === 'closeComputerUI') {
        root.style.display='none';
        computerData=null;
        releaseAction();
    }
});

document.getElementById('btn-close-win').onclick = closeOS;
document.getElementById('btn-close-dot').onclick = closeOS;
document.addEventListener('keydown', e => {
    if (e.key === 'Escape' && root.style.display === 'flex') closeOS();
});
