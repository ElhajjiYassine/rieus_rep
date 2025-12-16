// ============================================================================
// GANG REPUTATION CARD DEALER - UI SYSTEM
// ============================================================================

// DOM Elements
const appContainer = document.getElementById('app');
const closeBtn = document.querySelector('.btn-close');
const btnConfirm = document.getElementById('btnConfirm');
const btnCancel = document.querySelector('.btn-cancel');
const cardsGrid = document.getElementById('cardsGrid');
const emptyState = document.getElementById('emptyState');
const selectedPreview = document.getElementById('selectedPreview');
const previewIcon = document.getElementById('previewIcon');
const previewTitle = document.getElementById('previewTitle');
const previewRep = document.getElementById('previewRep');
const badgeCount = document.getElementById('badgeCount');
const statsAvailable = document.getElementById('statsAvailable');
const statsTotalRep = document.getElementById('statsTotalRep');
const loadingOverlay = document.getElementById('loadingOverlay');

// State
let currentCards = [];
let selectedCard = null;
let playerStats = {
    available: 0,
    totalRep: 0
};

// ============================================================================
// INITIALIZATION
// ============================================================================

document.addEventListener('DOMContentLoaded', function() {
    console.log('UI Script loaded');
    setupEventListeners();
    // Show welcome state
    emptyState.classList.add('show');
});

function setupEventListeners() {
    if (closeBtn) closeBtn.addEventListener('click', closeUI);
    if (btnConfirm) btnConfirm.addEventListener('click', giveCard);
    if (btnCancel) btnCancel.addEventListener('click', cancelGive);
    
    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape' && !appContainer.classList.contains('hidden')) {
            closeUI();
        }
    });
}

// ============================================================================
// NUI COMMUNICATION
// ============================================================================

window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (data.type === 'SHOW_UI') {
        showUI(data.cards, data.stats);
    } else if (data.type === 'CLOSE_UI') {
        closeUI();
    } else if (data.type === 'LOADING') {
        setLoading(data.show);
    }
});

function postNUI(method, data) {
    const resourceName = GetParentResourceName();
    const url = `https://${resourceName}/${method}`;
    
    console.log(`[NUI] Calling ${method} on ${resourceName}`, data);
    
    fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json; charset=UTF-8',
        },
        body: JSON.stringify(data)
    })
    .then(res => {
        console.log(`[NUI] ${method} response received:`, res.status, res.statusText);
        // FiveM NUI callbacks don't require JSON parsing
        return res;
    })
    .catch((error) => {
        // Note: In FiveM, fetch errors are expected for NUI callbacks
        // The callback is still registered even if fetch fails
        console.log(`[NUI] ${method} fetch completed (error expected):`, error.message);
    });
}

// ============================================================================
// UI VISIBILITY
// ============================================================================

function showUI(cards, stats) {
    currentCards = cards || [];
    playerStats = stats || { available: 0, totalRep: 0 };
    
    // Update stats
    updateStats();
    
    // Display cards
    displayCards();
    
    // Show UI
    appContainer.classList.remove('hidden');
    
    // Focus management
    document.addEventListener('keydown', preventGameKeys);
}

function closeUI() {
    appContainer.classList.add('hidden');
    selectedCard = null;
    selectedPreview.classList.remove('show');
    document.removeEventListener('keydown', preventGameKeys);
    postNUI('close', {});
}

function preventGameKeys(e) {
    if (['w', 'a', 's', 'd', 'e', 'q', 'space', 'control', 'shift'].includes(e.key.toLowerCase())) {
        e.preventDefault();
        return false;
    }
}

// ============================================================================
// STATS DISPLAY
// ============================================================================

function updateStats() {
    if (statsAvailable) {
        statsAvailable.textContent = playerStats.available;
    }
    if (statsTotalRep) {
        statsTotalRep.textContent = playerStats.totalRep;
    }
}

// ============================================================================
// CARDS DISPLAY
// ============================================================================

function displayCards() {
    cardsGrid.innerHTML = '';
    badgeCount.textContent = currentCards.length;
    
    if (!currentCards || currentCards.length === 0) {
        emptyState.classList.add('show');
        return;
    }
    
    emptyState.classList.remove('show');
    
    currentCards.forEach((card, index) => {
        const cardEl = createCardElement(card, index);
        cardsGrid.appendChild(cardEl);
    });
}

function createCardElement(card, index) {
    const cardDiv = document.createElement('div');
    cardDiv.className = 'card-item';
    cardDiv.id = `card-${index}`;
    cardDiv.style.cursor = 'pointer';
    
    const clickHandler = () => selectCard(index, card);
    cardDiv.addEventListener('click', clickHandler);
    
    // Escape HTML to prevent XSS
    const escapedLabel = escapeHtml(card.label || 'Unknown Card');
    const escapedDesc = escapeHtml(card.description || 'No description');
    const icon = card.icon || 'fa-star';
    const rep = card.reputation || 0;
    const quantity = card.quantity || 1;
    const quantityBadge = quantity > 1 ? `<span class="quantity-badge">${quantity}x</span>` : '';
    
    cardDiv.innerHTML = `
        <div class="card-icon">
            <i class="fas ${icon}"></i>
        </div>
        <div class="card-content">
            <div class="card-label">${escapedLabel}</div>
            <div class="card-description">${escapedDesc}</div>
        </div>
        <div class="card-rep-badge">${rep}</div>
        ${quantityBadge}
    `;
    
    return cardDiv;
}

// ============================================================================
// CARD SELECTION
// ============================================================================

function selectCard(index, card) {
    // Remove previous selection
    if (selectedCard !== null) {
        const prevCard = document.getElementById(`card-${selectedCard}`);
        if (prevCard) prevCard.classList.remove('selected');
    }
    
    // Select new card
    selectedCard = index;
    const currentCardEl = document.getElementById(`card-${index}`);
    if (currentCardEl) currentCardEl.classList.add('selected');
    
    // Update preview
    updatePreview(card);
}

function updatePreview(card) {
    if (!card) return;
    
    const icon = card.icon || 'fa-star';
    const label = escapeHtml(card.label || 'Unknown Card');
    const rep = card.reputation || 0;
    
    previewIcon.innerHTML = `<i class="fas ${icon}"></i>`;
    previewTitle.textContent = label;
    previewRep.textContent = rep;
    
    selectedPreview.classList.add('show');
}

// ============================================================================
// ACTIONS
// ============================================================================

function giveCard() {
    if (selectedCard === null || !currentCards[selectedCard]) {
        console.error('No card selected');
        return;
    }
    
    const card = currentCards[selectedCard];
    
    setLoading(true);
    if (btnConfirm) btnConfirm.disabled = true;
    
    // Delay to show loading state
    setTimeout(() => {
        postNUI('giveCard', {
            cardIndex: selectedCard,
            cardData: card
        });
        
        // Auto-close after timeout if no response
        setTimeout(() => {
            if (loadingOverlay.classList.contains('show')) {
                setLoading(false);
            }
        }, 5000);
    }, 300);
}

function cancelGive() {
    closeUI();
}

function setLoading(show) {
    if (show) {
        loadingOverlay.classList.add('show');
    } else {
        loadingOverlay.classList.remove('show');
        if (btnConfirm) btnConfirm.disabled = false;
    }
}

// ============================================================================
// UTILITIES
// ============================================================================

function escapeHtml(text) {
    const map = {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#039;'
    };
    return text.replace(/[&<>"']/g, m => map[m]);
}

function GetParentResourceName() {
    return 'rieus_rep';
}
