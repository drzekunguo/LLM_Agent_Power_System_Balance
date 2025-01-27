# AI_Power_System_Balance

This repository contains the codebase for leveraging Large Language Model (LLM) Agents to assist in decision-making for power system operations. It includes Jupyter Notebook and MATLAB scripts for various tasks related to power system balance.

## Repository Structure

- `Prob Generator.ipynb`: A Jupyter Notebook utilizing Microsoft's Autogen framework for probabilistic generation and system operation tasks.
- MATLAB Codes: Scripts that rely on optimization libraries for power system modeling and decision-making.

## Getting Started

### Setting Up the Environment for `Prob Generator.ipynb`

To run the `Prob Generator.ipynb`, follow these steps:

1. **Create a Conda Environment**:
   ```bash
   conda create -n autogen-env python=3.10
   ```

2. **Install the `autogen-agentchat` Package**:
   ```bash
   pip install autogen-agentchat~=0.2
   ```

3. **Create a Jupyter Notebook Kernel**:
   ```bash
   ipython kernel install --user --name=Autogen-kernel
   ```

4. **Run the Notebook**:
   - Open the `Prob Generator.ipynb` in Jupyter Notebook.
   - Ensure you select the `Autogen-kernel` before running the notebook.

### Dependencies for MATLAB Codes

The MATLAB scripts in this repository require the following dependencies:

1. **YALMIP**:
   Installation instructions are available here: [YALMIP Installation Guide](https://yalmip.github.io/tutorial/installation/)

2. **Gurobi Optimizer**:
   Ensure you have a valid Gurobi license and have installed the Gurobi MATLAB interface. Visit the [Gurobi website](https://www.gurobi.com/) for more details.

## Citation

If you find this repository useful, please consider citing the following paper:

```
@article{your_paper,
  author    = {Your Name and Co-Authors},
  title     = {Title of the Paper},
  journal   = {Journal Name},
  year      = {2025},
  volume    = {XX},
  number    = {YY},
  pages     = {ZZ-ZZ},
  doi       = {DOI URL},
}
```

## Contributing

Contributions are welcome! If you encounter any issues or have suggestions for improvements, feel free to open an issue or submit a pull request.

## License

This repository is licensed under the MIT License. See the `LICENSE` file for more details.
