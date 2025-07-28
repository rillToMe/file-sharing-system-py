document.addEventListener('DOMContentLoaded', () => {
    // Login Logic
    const loginForm = document.querySelector('#loginForm');
    const passwordInput = document.querySelector('#password');
    const loginButton = document.querySelector('#loginForm button[type="submit"]');

    if (loginForm && passwordInput && loginButton) {
        loginForm.addEventListener('submit', (e) => {
            e.preventDefault();
            const enteredPassword = passwordInput.value;
            const correctPassword = '{PASSWORD}';

            if (enteredPassword === correctPassword) {
                window.location.href = 'files.html';
            } else {
                alert('Password salah! Silakan coba lagi.');
                passwordInput.value = '';
            }
        });

        // Tombol Mata
        const eyeIcon = document.getElementById('eyeIcon');
        if (eyeIcon) {
            eyeIcon.addEventListener('click', () => {
                if (passwordInput.type === 'password') {
                    passwordInput.type = 'text';
                    eyeIcon.textContent = '👁️‍🗨️'; // Mata terbuka
                } else {
                    passwordInput.type = 'password';
                    eyeIcon.textContent = '👁️'; // Mata tertutup
                }
            });
        }
    }

    // Reset Password Logic (untuk forget.html)
    const resetButton = document.querySelector('#resetButton');
    if (resetButton && window.location.pathname.includes('forget.html')) {
        resetButton.addEventListener('click', async () => {
            try {
                await fetch('/__FORGET_FLAG.txt', {
                    method: 'PUT',
                    body: 'reset'
                });
                alert('Permintaan reset password dikirim. Periksa server.');
                window.location.href = 'index.html';
            } catch (error) {
                alert('Gagal mengirim permintaan reset. Coba lagi.');
                console.error(error);
            }
        });
    }
});