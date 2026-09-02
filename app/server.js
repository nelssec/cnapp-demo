const express = require('express');
const _ = require('lodash');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => res.json({ service: 'cnapp-demo', status: 'ok' }));
app.get('/health', (req, res) => res.send('ok'));
app.get('/merge', (req, res) => res.json(_.merge({}, req.query)));

app.listen(port, () => console.log(`cnapp-demo listening on ${port}`));
