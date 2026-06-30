const express = require('express');
const _ = require('lodash');

const app = express();
const PORT = 8080;

app.get('/', (req, res) => {
  res.send('Vulnerable App Running - Lodash ' + _.VERSION);
});

app.listen(PORT, () => {
  console.log(`App running on port ${PORT}`);
});
