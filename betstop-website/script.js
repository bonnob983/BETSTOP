// Close button functionality
document.querySelectorAll('.control-btn.close').forEach(btn => {
    btn.addEventListener('click', function() {
        this.closest('.window').style.display = 'none';
    });
});

// Minimize button (collapse window body)
document.querySelectorAll('.control-btn.minimize').forEach(btn => {
    btn.addEventListener('click', function() {
        const windowBody = this.closest('.window').querySelector('.window-body');
        if (windowBody.style.display === 'none') {
            windowBody.style.display = 'block';
        } else {
            windowBody.style.display = 'none';
        }
    });
});
