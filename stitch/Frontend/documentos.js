const API_URL = `http://${window.location.hostname}:8000`;
const gridContainer = document.getElementById('gridContainer');
const gridSort = document.getElementById('gridSort');

document.addEventListener('DOMContentLoaded', () => {
    fetchGrid();
    
    gridSort.addEventListener('change', () => {
        fetchGrid(gridSort.value);
    });
});

async function fetchGrid(order = 'recientes') {
    gridContainer.innerHTML = '<div class="col-span-full text-center py-10 text-on-surface-variant">Cargando...</div>';
    try {
        // Pedimos más elementos para el grid view
        const res = await fetch(`${API_URL}/documentos?por_pagina=20`);
        const data = await res.json();
        
        let items = data.items;
        if (order === 'antiguos') {
            items.reverse();
        }
        
        renderGrid(items);
    } catch (e) {
        gridContainer.innerHTML = '<div class="col-span-full text-center py-10 text-error">Error al cargar documentos</div>';
    }
}

function renderGrid(items) {
    if (items.length === 0) {
        gridContainer.innerHTML = '<div class="col-span-full text-center py-10 text-on-surface-variant">No hay documentos disponibles</div>';
        return;
    }
    
    gridContainer.innerHTML = '';
    items.forEach(doc => {
        let estadoColor = "bg-gray-100 text-gray-800";
        if (doc.estado === "completado") estadoColor = "bg-green-100 text-green-800";
        if (doc.estado === "pendiente") estadoColor = "bg-amber-100 text-amber-800";
        if (doc.estado === "en_revision") estadoColor = "bg-blue-100 text-blue-800";
        
        const card = document.createElement('div');
        card.className = "bg-surface-container-lowest rounded-xl border border-outline-variant shadow-sm hover:shadow-md transition-shadow p-5 flex flex-col items-center group cursor-pointer relative";
        
        // Use an invisible absolute overlay for download trigger, or a specific button
        card.innerHTML = `
            <div class="absolute top-3 right-3">
                <button onclick="downloadDoc('${doc.folio}'); event.stopPropagation();" class="opacity-0 group-hover:opacity-100 p-2 text-on-surface-variant hover:text-primary hover:bg-surface-container-low rounded-lg transition-all" title="Descargar">
                    <span class="material-symbols-outlined text-[20px]">download</span>
                </button>
            </div>
            <div class="w-16 h-16 rounded-2xl bg-primary-container/10 flex items-center justify-center mb-4 mt-2">
                <span class="material-symbols-outlined text-primary text-[40px]">${doc.icono || 'description'}</span>
            </div>
            <h3 class="text-body-md font-bold text-on-surface text-center line-clamp-2 w-full mb-1" title="${doc.nombre}">${doc.nombre}</h3>
            <div class="text-label-sm text-on-surface-variant mb-3">${doc.folio}</div>
            
            <span class="mt-auto px-3 py-1 rounded-full text-[10px] font-bold ${estadoColor}">
                ${doc.estado.charAt(0).toUpperCase() + doc.estado.slice(1).replace('_', ' ')}
            </span>
        `;
        gridContainer.appendChild(card);
    });
}

window.downloadDoc = function(folio) {
    window.open(`${API_URL}/documentos/${folio}/descargar`, '_blank');
}
