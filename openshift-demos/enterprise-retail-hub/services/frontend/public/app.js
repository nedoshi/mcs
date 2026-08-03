/**
 * Storefront client — calls API Gateway via same-origin /api proxy.
 */
const SESSION_KEY = 'retail-hub-session';

function getSessionId() {
  let id = localStorage.getItem(SESSION_KEY);
  if (!id) {
    id = crypto.randomUUID();
    localStorage.setItem(SESSION_KEY, id);
  }
  return id;
}

const sessionId = getSessionId();
document.getElementById('session-id').textContent = sessionId.slice(0, 8) + '…';

const productGrid = document.getElementById('product-grid');
const cartItems = document.getElementById('cart-items');
const cartCount = document.getElementById('cart-count');
const cartTotal = document.getElementById('cart-total');
const checkoutStatus = document.getElementById('checkout-status');

function formatPrice(cents) {
  return `$${(cents / 100).toFixed(2)}`;
}

async function fetchProducts() {
  const res = await fetch('/api/products');
  const products = await res.json();
  productGrid.innerHTML = products.map((p) => `
    <article class="product-card" data-id="${p.id}">
      <img src="${p.image_url}" alt="${p.name}" onerror="this.src='/images/placeholder.svg'" />
      <span class="category">${p.category}</span>
      <h3>${p.name}</h3>
      <p>${p.description}</p>
      <span class="price">${formatPrice(p.price_cents)}</span>
      <span class="stock">${p.stock} in stock</span>
      <button class="btn btn-add" data-product='${JSON.stringify(p)}'>Add to Cart</button>
    </article>
  `).join('');

  productGrid.querySelectorAll('.btn-add').forEach((btn) => {
    btn.addEventListener('click', () => addToCart(JSON.parse(btn.dataset.product)));
  });
}

async function loadCart() {
  const res = await fetch(`/api/cart/${sessionId}`);
  const data = await res.json();
  renderCart(data.items);
}

function renderCart(items) {
  const count = items.reduce((sum, i) => sum + i.quantity, 0);
  cartCount.textContent = count;

  if (items.length === 0) {
    cartItems.innerHTML = '<li>Cart is empty</li>';
    cartTotal.textContent = '$0.00';
    return;
  }

  cartItems.innerHTML = items.map((i) =>
    `<li>${i.name} × ${i.quantity} — ${formatPrice(i.priceCents * i.quantity)}</li>`
  ).join('');

  const total = items.reduce((sum, i) => sum + i.priceCents * i.quantity, 0);
  cartTotal.textContent = formatPrice(total);
}

async function addToCart(product) {
  const res = await fetch(`/api/cart/${sessionId}/items`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      productId: product.id,
      name: product.name,
      priceCents: product.price_cents,
      quantity: 1,
      maxStock: product.stock,
    }),
  });

  if (!res.ok) {
    const err = await res.json();
    checkoutStatus.textContent = err.error || 'Could not add item';
    checkoutStatus.className = 'status error';
    return;
  }

  const data = await res.json();
  renderCart(data.items);
  checkoutStatus.textContent = `Added ${product.name}`;
  checkoutStatus.className = 'status success';
}

async function checkout() {
  const email = document.getElementById('customer-email').value.trim();
  if (!email) {
    checkoutStatus.textContent = 'Enter your work email';
    checkoutStatus.className = 'status error';
    return;
  }

  const cartRes = await fetch(`/api/cart/${sessionId}`);
  const cart = await cartRes.json();

  if (cart.items.length === 0) {
    checkoutStatus.textContent = 'Cart is empty';
    checkoutStatus.className = 'status error';
    return;
  }

  const res = await fetch('/api/orders', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      sessionId,
      customerEmail: email,
      items: cart.items,
    }),
  });

  const result = await res.json();

  if (!res.ok) {
    checkoutStatus.textContent = result.error || 'Checkout failed';
    checkoutStatus.className = 'status error';
    return;
  }

  checkoutStatus.textContent = `Order ${result.orderNumber} confirmed — ${formatPrice(result.totalCents)}`;
  checkoutStatus.className = 'status success';
  renderCart([]);
  fetchProducts();
}

document.getElementById('checkout-btn').addEventListener('click', checkout);
document.getElementById('cart-toggle').addEventListener('click', () => {
  document.getElementById('cart-panel').classList.toggle('hidden');
});

fetchProducts();
loadCart();
