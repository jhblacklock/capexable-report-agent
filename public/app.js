document.addEventListener('DOMContentLoaded', function() {
    // Function to add event listeners to all remove buttons
    function addRemoveButtonListeners() {
        document.querySelectorAll('.remove-user-btn').forEach(btn => {
            btn.addEventListener('click', function(event) {
                event.preventDefault(); // Prevent form submission
                var accountId = this.getAttribute('data-account-id');
                console.log('Removing user with accountId: ', accountId);

                fetch('/remove_user', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ account_id: accountId })
                })
                .then(function(response) {
                    if (response.ok) {
                        // Optionally handle success (e.g., remove the user from the list)
                        location.reload(); // Reload the page or update the UI accordingly
                    } else if (response.status === 409) {
                        console.log('User already exists in the list');
                    } else {
                        throw new Error('Error removing user');
                    }
                })
                .catch(function(error) {
                    // Handle error
                    alert('Error removing user: ' + error.message);
                });
            });
        });
    }

    // Add event listeners to existing remove buttons on page load
    addRemoveButtonListeners();

    document.querySelectorAll('.add-user-btn').forEach(btn => {
        btn.addEventListener('click', async () => {
            const accountId = btn.dataset.accountId;
            const displayName = btn.dataset.displayName;

            const response = await fetch('/add_user', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ add_user: { account_id: accountId, display_name: displayName } })
            });

            if (response.ok) {
                const selectedUsersList = document.querySelector('#selected-users');
                const noSelectedUsersItem = selectedUsersList.querySelector('li:first-child');
                if (noSelectedUsersItem && noSelectedUsersItem.textContent === 'No selected users') {
                    selectedUsersList.removeChild(noSelectedUsersItem);
                }
                const listItem = document.createElement('li');
                listItem.innerHTML = `
                    ${displayName}
                    <button type="button" class="remove-user-btn" data-account-id="${accountId}">Remove</button>
                `;
                selectedUsersList.appendChild(listItem);
                const assigneeList = document.querySelector('#assignee-list');
                const hiddenInput = document.createElement('input');
                hiddenInput.type = 'hidden';
                hiddenInput.name = 'assignees[]';
                hiddenInput.value = accountId;
                assigneeList.appendChild(hiddenInput);

                // Add event listener to the newly created remove button
                addRemoveButtonListeners(); // Reattach listeners to all remove buttons
            }
        });
    });
});
