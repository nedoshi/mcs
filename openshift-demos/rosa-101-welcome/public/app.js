async function loadRuntimeInfo() {
  const statusEl = document.getElementById('status');
  const hostnameEl = document.getElementById('hostname');
  const namespaceEl = document.getElementById('namespace');
  const versionEl = document.getElementById('version');
  const titleEl = document.getElementById('welcome-title');

  try {
    const response = await fetch('/api/info');
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const info = await response.json();
    titleEl.textContent = info.message;
    statusEl.textContent = 'Healthy';
    hostnameEl.textContent = info.hostname;
    namespaceEl.textContent = info.namespace;
    versionEl.textContent = info.appVersion;
  } catch (error) {
    statusEl.textContent = 'Unavailable';
    hostnameEl.textContent = error.message;
  }
}

async function loadProducts() {
  const grid = document.getElementById('product-grid');

  try {
    const response = await fetch('/api/products');
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const products = await response.json();
    grid.innerHTML = products
      .map(
        (product) => `
          <article class="product-card">
            <h3>${product.name}</h3>
            <p class="product-meta">${product.category} · ${product.stock} in stock</p>
            <p class="product-price">${product.price === 0 ? 'Free' : `$${product.price.toFixed(2)}`}</p>
          </article>
        `
      )
      .join('');
  } catch (error) {
    grid.innerHTML = `<p>Could not load catalog: ${error.message}</p>`;
  }
}

loadRuntimeInfo();
loadProducts();
