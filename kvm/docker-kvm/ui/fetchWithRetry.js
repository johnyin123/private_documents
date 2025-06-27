// Fetch with retry functionality
const fetchWithRetry = async (url, options = {}, retries = 2, delay = 1000) => {
  try {
    const response = await fetch(url, options);
    if (response.ok) return response;
    throw new Error(`HTTP error! Status: ${response.status}`);
  } catch (error) {
    if (retries <= 0) throw error;
    // Wait for the specified delay
    await new Promise(resolve => setTimeout(resolve, delay));
    // Retry with one less retry attempt
    console.log(`Retrying fetch to ${url}, ${retries} attempts left`);
    return fetchWithRetry(url, options, retries - 1, delay);
  }
};

const fetchVMs = async () => {
  try {
    // const opts = {
    //     method: method,
    //     headers: { 'Content-Type': 'application/json', },
    //     body: data ? JSON.stringify(data) : null,
    // };
    const response = await fetchWithRetry('/api/vms', {}, 2, 1000);
    if (!response.ok) {
      throw new Error(`HTTP error! Status: ${response.status}`);
    }
    const data = await response.json();
    //////////.........//////////
  } catch (error) {
    console.error('Error fetching VM data:', error);
    // More detailed error message
    const errorMessage = error.message || 'Unknown error';
    showMessage(`Error loading VM data: ${errorMessage}. Please try again later.`, 'error');
  }
};

